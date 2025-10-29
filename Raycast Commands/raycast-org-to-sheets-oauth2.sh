#!/usr/bin/env bash
set -euo pipefail

# Raycast Script: Emacs Org Mode to Google Sheets Sync (OAuth2 Version)
# This version uses OAuth2 for authentication - easier to set up than service accounts

# Configuration
ORG_FILE="INPUT HERE"
SHEET_ID="INPUT HERE"  # Replace with your actual Google Sheets ID
SHEET_NAME="Time Table Archive"  # Change this to your sheet name if different
API_KEY="INPUT HERE"
CLIENT_ID="INPUT HERE"
CLIENT_SECRET="INPUT HERE"
TOKEN_FILE="INPUT HERE"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1" >&2
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

print_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1" >&2
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
        current_course_abbrev = ""
        current_event = ""
        in_logbook = 0
        clock_entries = ""
    }
    
    # Match course headers (e.g., "* Math 210A-Real Analysis:")
    /^\* [^*]/ {
        gsub(/^\* /, "", $0)
        gsub(/:$/, "", $0)
        current_course = $0
        # Abbreviate course to: Letters + space + digits (drop trailing letter and title)
        # Examples:
        #  - "MAE 112—Propulsion" -> "MAE 112"
        #  - "Math 210A-Real Analysis" -> "Math 210"
        #  - "Writing 60-Argument & Research" -> "Writing 60"
        if (match(current_course, /^[A-Za-z]+[[:space:]]+[0-9]/)) {
            current_course_abbrev = substr(current_course, RSTART, RLENGTH)
        } else {
            current_course_abbrev = current_course
        }
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
            print current_course_abbrev "\t" current_event "\t" clock_entries
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
}

# Get OAuth2 access token
get_access_token() {
    print_status "Getting OAuth2 access token..."
    
    # Check if we have a stored token
    if [ -f "$TOKEN_FILE" ]; then
        local token=$(jq -r '.access_token' "$TOKEN_FILE")
        local expires_at=$(jq -r '.expires_at' "$TOKEN_FILE")
        local now=$(date +%s)
        
        # Check if token is still valid (with 5 minute buffer)
        if [ "$expires_at" != "null" ] && [ "$expires_at" -gt $((now + 300)) ]; then
            print_status "Using cached access token"
            echo "$token"
            return
        fi
    fi
    
    # Check if we have refresh token
    if [ -f "$TOKEN_FILE" ] && [ "$(jq -r '.refresh_token' "$TOKEN_FILE")" != "null" ]; then
        print_status "Refreshing access token..."
        local refresh_token=$(jq -r '.refresh_token' "$TOKEN_FILE")
        
        local response=$(curl -s -X POST \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET&refresh_token=$refresh_token&grant_type=refresh_token" \
            "https://oauth2.googleapis.com/token")
        
        local access_token=$(echo "$response" | jq -r '.access_token')
        
        if [ "$access_token" != "null" ] && [ -n "$access_token" ]; then
            # Update token file with new access token
            local expires_in=$(echo "$response" | jq -r '.expires_in')
            local expires_at=$(( $(date +%s) + expires_in ))
            
            jq --arg token "$access_token" --arg expires_at "$expires_at" \
                '.access_token = $token | .expires_at = $expires_at' \
                "$TOKEN_FILE" > "$TOKEN_FILE.tmp" && mv "$TOKEN_FILE.tmp" "$TOKEN_FILE"
            
            echo "$access_token"
            return
        fi
    fi
    
    # Need to do initial OAuth2 flow
    print_error "No valid token found. You need to complete the OAuth2 flow first."
    print_error "Run the setup script to authenticate with Google."
    exit 1
}

# Find the first empty row in the Google Sheet
find_empty_row() {
    local access_token="$1"
    
    print_status "Finding first row where column B is empty (skipping header row 1)..."
    
    # Use includeGridData so empty cells are explicit in the response
    local url="https://sheets.googleapis.com/v4/spreadsheets/${SHEET_ID}"
    local response
    response=$(curl -s -G \
        -H "Authorization: Bearer ${access_token}" \
        --data-urlencode "ranges=${SHEET_NAME}!B2:B2000" \
        --data-urlencode "includeGridData=true" \
        --data-urlencode "fields=sheets(data.rowData.values.userEnteredValue)" \
        "$url")
    
    if echo "$response" | jq -e '.error' > /dev/null 2>&1; then
        print_error "Failed to read sheet: $(echo "$response" | jq -r '.error.message')"
        exit 1
    fi
    
    # Find first rowData entry with missing/empty userEnteredValue
    local first_empty_index
    first_empty_index=$(echo "$response" | jq -r '
        ( .sheets[0].data[0].rowData // [] )
        | to_entries
        | map(select(.value == null
                     or (.value.values | length == 0)
                     or (.value.values[0].userEnteredValue == null)))
        | if length == 0 then empty else .[0].key end')
    
    if [ -z "$first_empty_index" ]; then
        # No empty found within B2:B2000; append after the last materialized row
        local row_count
        row_count=$(echo "$response" | jq -r '(.sheets[0].data[0].rowData // []) | length')
        echo $((row_count + 2))
        return
    fi
    
    echo $((first_empty_index + 2))
}

# Upload data to Google Sheets
upload_to_sheets() {
    local access_token="$1"
    local start_row="$2"
    
    print_status "Uploading data to Google Sheets starting at row $start_row..."
    
    local current_row="$start_row"
    
    while IFS=$'\t' read -r course event clock_data; do
        # Iterate each LOGBOOK clock line without subshell so row increments persist
        while IFS=$'\t' read -r clock_in clock_out; do
            if [ -n "$clock_in" ] && [ -n "$clock_out" ]; then
                print_status "Uploading: $course - $event ($clock_in to $clock_out)"
                
                # Create JSON payload with explicit majorDimension
                local json=$(jq -n --arg c "$course" --arg e "$event" --arg ci "$clock_in" --arg co "$clock_out" \
                    '{range: null, majorDimension: "ROWS", values: [[ $c, $e, $ci, $co ]] }')

                # URL-encode the range to handle spaces in sheet names
                local range_enc
                range_enc=$(jq -rn --arg r "$SHEET_NAME!A${current_row}:D${current_row}" '$r|@uri')

                # Perform PUT update to explicit row range and capture HTTP status
                local body_file http_code
                body_file=$(mktemp)
                http_code=$(curl -s -X PUT \
                    -H "Authorization: Bearer $access_token" \
                    -H "Content-Type: application/json" \
                    -d "$json" \
                    -o "$body_file" -w "%{http_code}" \
                    "https://sheets.googleapis.com/v4/spreadsheets/$SHEET_ID/values/$range_enc?valueInputOption=USER_ENTERED")

                if [ "$http_code" != "200" ]; then
                    local err_msg
                    err_msg=$(cat "$body_file" | jq -r '.error.message // "Unknown error"')
                    print_error "Failed to upload row $current_row (HTTP $http_code): $err_msg"
                    rm -f "$body_file"
                    # Stop on first error to avoid cascading issues
                    return 1
                fi

                local updated_range
                updated_range=$(cat "$body_file" | jq -r '.updatedRange // empty')
                rm -f "$body_file"
                if [ -z "$updated_range" ]; then
                    print_warning "No updatedRange returned for row $current_row; verify sheet name and permissions"
                    return 1
                fi

                print_status "Successfully uploaded row $current_row (updatedRange: $updated_range)"
                ((current_row++))
            fi
        done <<< "$clock_data"
    done < /tmp/org_done_parsed.tsv
}

# Main execution
main() {
    print_status "Starting org-to-sheets sync (OAuth2 Version)..."
    
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
    
    # Check if OAuth2 credentials are configured
    if [ "$CLIENT_ID" = "YOUR_CLIENT_ID" ] || [ "$CLIENT_SECRET" = "YOUR_CLIENT_SECRET" ]; then
        print_error "Please configure CLIENT_ID and CLIENT_SECRET in the script"
        print_error "Get these from Google Cloud Console > APIs & Services > Credentials"
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
