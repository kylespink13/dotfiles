#!/usr/bin/env bash
set -euo pipefail

# Configuration
ORG_FILE="INPUT HERE"
SHEET_ID="YOUR_SPREADSHEET_ID"  # Replace with your actual Google Sheets ID
SHEET_NAME="Sheet1"  # Change this to your sheet name if different
API_KEY="INPUT HERE"
SERVICE_ACCOUNT_KEY="INPUT HERE"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# Check if required tools are installed
check_dependencies() {
    local missing_deps=()
    
    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi
    
    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi
    
    if ! command -v openssl &> /dev/null; then
        missing_deps+=("openssl")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_error "Missing dependencies: ${missing_deps[*]}"
        print_error "Please install them using: brew install ${missing_deps[*]}"
        exit 1
    fi
}

# Parse the org file for DONE entries
parse_org_file() {
    print_status "Parsing org file for DONE entries..."
    
    awk '
    BEGIN {
        current_course = ""
        current_event = ""
        in_logbook = 0
        clock_entries = ""
    }
    
    # Match course headers (e.g., "* Math 210A-Real Analysis:")
    /^\* [^*]/ {
        gsub(/^\* /, "", $0)
        gsub(/:$/, "", $0)
        current_course = $0
        next
    }
    
    # Match DONE entries
    /^\*\*\* DONE/ {
        # Extract the event name, removing the DONE keyword and priority
        current_event = $0
        gsub(/^\*\*\* DONE \[#[A-Z]\] /, "", current_event)
        gsub(/\[\[.*?\]\[/, "", current_event)
        gsub(/\]\]$/, "", current_event)
        gsub(/^\[\[/, "", current_event)
        next
    }
    
    # Start of LOGBOOK
    /^:LOGBOOK:/ {
        in_logbook = 1
        clock_entries = ""
        next
    }
    
    # End of LOGBOOK
    /^:END:/ {
        if (in_logbook && clock_entries != "") {
            print current_course "\t" current_event "\t" clock_entries
        }
        in_logbook = 0
        clock_entries = ""
        next
    }
    
    # Parse CLOCK entries
    /^CLOCK:/ && in_logbook {
        # Extract clock times using regex
        if (match($0, /\[([^\]]+)\]--\[([^\]]+)\]/)) {
            clock_in = substr($0, RSTART+1, RLENGTH-1)
            gsub(/\[|\]/, "", clock_in)
            split(clock_in, times, "--")
            if (length(times) == 2) {
                if (clock_entries != "") clock_entries = clock_entries "\n"
                clock_entries = clock_entries times[1] "\t" times[2]
            }
        }
    }
    ' "$ORG_FILE" > /tmp/org_done_parsed.tsv
    
    if [ ! -s /tmp/org_done_parsed.tsv ]; then
        print_warning "No DONE entries with clock data found in the org file"
        exit 0
    fi
    
    print_status "Found $(wc -l < /tmp/org_done_parsed.tsv) DONE entries with clock data"
    
    # Debug: show what we parsed
    print_debug "Parsed data:"
    cat /tmp/org_done_parsed.tsv | while IFS=$'\t' read -r course event clock_data; do
        print_debug "Course: $course"
        print_debug "Event: $event"
        print_debug "Clock data: $clock_data"
        echo "---"
    done
}

# Create JWT token for Google Sheets API
create_jwt_token() {
    local header='{"alg":"RS256","typ":"JWT"}'
    local now=$(date +%s)
    local exp=$((now + 3600))  # Token expires in 1 hour
    
    # Read service account key
    local client_email=$(jq -r '.client_email' "$SERVICE_ACCOUNT_KEY")
    local private_key=$(jq -r '.private_key' "$SERVICE_ACCOUNT_KEY")
    
    # Create payload
    local payload=$(jq -n \
        --arg iss "$client_email" \
        --arg scope "https://www.googleapis.com/auth/spreadsheets" \
        --arg aud "https://oauth2.googleapis.com/token" \
        --arg exp "$exp" \
        --arg iat "$now" \
        '{
            iss: $iss,
            scope: $scope,
            aud: $aud,
            exp: ($exp | tonumber),
            iat: ($iat | tonumber)
        }')
    
    # Encode header and payload
    local encoded_header=$(echo -n "$header" | base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n')
    local encoded_payload=$(echo -n "$payload" | base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n')
    
    # Create signature
    local signature_input="${encoded_header}.${encoded_payload}"
    local signature=$(echo -n "$signature_input" | openssl dgst -sha256 -sign <(echo "$private_key") | base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n')
    
    # Create JWT
    echo "${signature_input}.${signature}"
}

# Get Google Sheets access token using service account
get_access_token() {
    print_status "Getting Google Sheets access token..."
    
    # Check if service account key exists
    if [ ! -f "$SERVICE_ACCOUNT_KEY" ]; then
        print_error "Service account key not found at $SERVICE_ACCOUNT_KEY"
        print_error "Please set up a Google Cloud service account and download the JSON key file"
        print_error "Instructions:"
        print_error "1. Go to Google Cloud Console"
        print_error "2. Create a new project or select existing one"
        print_error "3. Enable Google Sheets API"
        print_error "4. Create a service account"
        print_error "5. Download the JSON key file"
        print_error "6. Place it at $SERVICE_ACCOUNT_KEY"
        exit 1
    fi
    
    # Create JWT token
    local jwt_token=$(create_jwt_token)
    
    # Exchange JWT for access token
    local response=$(curl -s -X POST \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=$jwt_token" \
        "https://oauth2.googleapis.com/token")
    
    local access_token=$(echo "$response" | jq -r '.access_token')
    
    if [ "$access_token" = "null" ] || [ -z "$access_token" ]; then
        print_error "Failed to get access token"
        print_error "Response: $response"
        exit 1
    fi
    
    echo "$access_token"
}

# Find the first empty row in the Google Sheet
find_empty_row() {
    local access_token="$1"
    
    print_status "Finding first empty row in Google Sheet..."
    
    # Get all data from column A to find the last row
    local response=$(curl -s -X GET \
        -H "Authorization: Bearer $access_token" \
        "https://sheets.googleapis.com/v4/spreadsheets/$SHEET_ID/values/$SHEET_NAME!A:A")
    
    if echo "$response" | jq -e '.error' > /dev/null; then
        print_error "Failed to read sheet: $(echo "$response" | jq -r '.error.message')"
        exit 1
    fi
    
    # Count non-empty rows
    local row_count=$(echo "$response" | jq -r '.values | length // 0')
    local next_row=$((row_count + 1))
    
    print_status "Next empty row: $next_row"
    echo "$next_row"
}

# Upload data to Google Sheets
upload_to_sheets() {
    local access_token="$1"
    local start_row="$2"
    
    print_status "Uploading data to Google Sheets starting at row $start_row..."
    
    local current_row="$start_row"
    
    while IFS=$'\t' read -r course event clock_data; do
        # Split multiple clock entries
        echo "$clock_data" | while IFS=$'\t' read -r clock_in clock_out; do
            if [ -n "$clock_in" ] && [ -n "$clock_out" ]; then
                print_status "Uploading: $course - $event ($clock_in to $clock_out)"
                
                # Create JSON payload
                local json=$(jq -n --arg c "$course" --arg e "$event" --arg ci "$clock_in" --arg co "$clock_out" \
                    '{values: [[ $c, $e, $ci, $co ]] }')
                
                # Upload to Google Sheets
                local response=$(curl -s -X POST \
                    -H "Authorization: Bearer $access_token" \
                    -H "Content-Type: application/json" \
                    -d "$json" \
                    "https://sheets.googleapis.com/v4/spreadsheets/$SHEET_ID/values/$SHEET_NAME!A$current_row:D$current_row?valueInputOption=USER_ENTERED")
                
                if echo "$response" | jq -e '.error' > /dev/null; then
                    print_error "Failed to upload row: $(echo "$response" | jq -r '.error.message')"
                else
                    print_status "Successfully uploaded row $current_row"
                    ((current_row++))
                fi
            fi
        done
    done < /tmp/org_done_parsed.tsv
}

# Main execution
main() {
    print_status "Starting org-to-sheets sync..."
    
    # Check dependencies
    check_dependencies
    
    # Check if org file exists
    if [ ! -f "$ORG_FILE" ]; then
        print_error "Org file not found: $ORG_FILE"
        exit 1
    fi
    
    # Check if SHEET_ID is configured
    if [ "$SHEET_ID" = "YOUR_SPREADSHEET_ID" ]; then
        print_error "Please configure SHEET_ID in the script"
        print_error "You can find your sheet ID in the URL: https://docs.google.com/spreadsheets/d/SHEET_ID/edit"
        exit 1
    fi
    
    # Parse org file
    parse_org_file
    
    # Get access token
    local access_token=$(get_access_token)
    
    # Find empty row
    local empty_row=$(find_empty_row "$access_token")
    
    # Upload data
    upload_to_sheets "$access_token" "$empty_row"
    
    print_status "Sync completed successfully!"
}

# Run main function
main "$@"