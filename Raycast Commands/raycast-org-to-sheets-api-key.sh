#!/usr/bin/env bash
set -euo pipefail

# Raycast Script: Emacs Org Mode to Google Sheets Sync (API Key Version)
# NOTE: This version uses API key for READ operations but requires OAuth2 for WRITE operations
# For full functionality, you'll need to set up OAuth2 or service account authentication

# Configuration
ORG_FILE="INPUT HERE"
SHEET_ID="INPUT HERE"  # Replace with your actual Google Sheets ID
SHEET_NAME="Time Table Archive"  # Change this to your sheet name if different
API_KEY="INPUT HERE"

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

# Find the first empty row in the Google Sheet (READ operation - works with API key)
find_empty_row() {
    print_status "Finding first empty row in Google Sheet..."
    
    # Get all data from column A to find the last row
    local response=$(curl -s -X GET \
        "https://sheets.googleapis.com/v4/spreadsheets/$SHEET_ID/values/$SHEET_NAME!A:A?key=$API_KEY")
    
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

# Generate CSV data for manual import
generate_csv() {
    print_status "Generating CSV data for manual import..."
    
    local csv_file="/tmp/org_data_$(date +%Y%m%d_%H%M%S).csv"
    
    # Add CSV header
    echo "Course,Event,Clock In,Clock Out" > "$csv_file"
    
    # Add data rows
    while IFS=$'\t' read -r course event clock_data; do
        # Split multiple clock entries
        echo "$clock_data" | while IFS=$'\t' read -r clock_in clock_out; do
            if [ -n "$clock_in" ] && [ -n "$clock_out" ]; then
                # Escape commas and quotes in CSV
                course_escaped=$(echo "$course" | sed 's/,/\\,/g' | sed 's/"/\\"/g')
                event_escaped=$(echo "$event" | sed 's/,/\\,/g' | sed 's/"/\\"/g')
                clock_in_escaped=$(echo "$clock_in" | sed 's/,/\\,/g' | sed 's/"/\\"/g')
                clock_out_escaped=$(echo "$clock_out" | sed 's/,/\\,/g' | sed 's/"/\\"/g')
                
                echo "\"$course_escaped\",\"$event_escaped\",\"$clock_in_escaped\",\"$clock_out_escaped\"" >> "$csv_file"
            fi
        done
    done < /tmp/org_done_parsed.tsv
    
    print_status "CSV file generated: $csv_file"
    print_status "You can manually copy this data to your Google Sheet"
    
    # Display the CSV content
    echo ""
    print_status "CSV Content:"
    cat "$csv_file"
    
    # Try to open the CSV file
    if command -v open &> /dev/null; then
        print_status "Opening CSV file..."
        open "$csv_file"
    fi
}

# Main execution
main() {
    print_status "Starting org-to-sheets sync (API Key Version)..."
    
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
    
    # Find empty row (this works with API key)
    local empty_row=$(find_empty_row)
    
    # Generate CSV for manual import (since API key can't write)
    generate_csv
    
    print_warning "IMPORTANT: API keys can only READ from Google Sheets, not WRITE"
    print_warning "To enable automatic writing, you need to set up OAuth2 or service account authentication"
    print_warning "See SETUP_GUIDE.md for detailed instructions"
    
    print_status "Sync completed! Check the generated CSV file for your data."
}

# Run main function
main "$@"
