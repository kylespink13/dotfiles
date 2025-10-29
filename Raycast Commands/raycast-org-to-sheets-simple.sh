#!/usr/bin/env bash
set -euo pipefail

# Raycast Script: Emacs Org Mode to Google Sheets Sync (Simplified Version)
# This version uses Google Apps Script to handle the writing, avoiding OAuth2 complexity

# Configuration
ORG_FILE="INPUT HERE"
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
}

# Generate formatted output for manual copy
generate_formatted_output() {
    print_status "Generating formatted output for manual copy..."
    
    echo ""
    print_status "=== DATA TO COPY TO GOOGLE SHEETS ==="
    echo ""
    
    while IFS=$'\t' read -r course event clock_data; do
        # Split multiple clock entries
        echo "$clock_data" | while IFS=$'\t' read -r clock_in clock_out; do
            if [ -n "$clock_in" ] && [ -n "$clock_out" ]; then
                echo "$course	$event	$clock_in	$clock_out"
            fi
        done
    done < /tmp/org_done_parsed.tsv
    
    echo ""
    print_status "=== INSTRUCTIONS ==="
    print_status "1. Copy the data above (between the === markers)"
    print_status "2. Open your Google Sheet: https://docs.google.com/spreadsheets/d/1mlCwtunvXCCD5Ik4OHzovHYS700e5t0vtXbFwN3ED0s/edit"
    print_status "3. Find the first empty row"
    print_status "4. Paste the data (it will automatically format into columns)"
    print_status "5. The columns will be: Course | Event | Clock In | Clock Out"
    echo ""
}

# Generate CSV file
generate_csv() {
    print_status "Generating CSV file..."
    
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
    
    # Try to open the CSV file
    if command -v open &> /dev/null; then
        print_status "Opening CSV file..."
        open "$csv_file"
    fi
}

# Main execution
main() {
    print_status "Starting org-to-sheets sync (Simplified Version)..."
    
    # Check dependencies
    check_dependencies
    
    # Check if org file exists
    if [ ! -f "$ORG_FILE" ]; then
        print_error "Org file not found: $ORG_FILE"
        exit 1
    fi
    
    # Parse org file
    parse_org_file
    
    # Generate formatted output
    generate_formatted_output
    
    # Generate CSV file
    generate_csv
    
    print_status "Sync completed! You can now manually copy the data to your Google Sheet."
}

# Run main function
main "$@"
