#!/usr/bin/env bash
set -euo pipefail

# OAuth2 Setup Script for Google Sheets API
# This script helps you set up OAuth2 authentication for the Google Sheets API
# Recommended: Create an OAuth Client ID with Application type "TVs and Limited Input devices"

# Configuration
CLIENT_ID="INPUT HERE"
CLIENT_SECRET="INPUT HERE"  # Unused for device flow
TOKEN_FILE="INPUT HERE"
# Device flow does not require a redirect URI

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

start_device_flow() {
    local scope="https://www.googleapis.com/auth/spreadsheets"
    print_status "Initiating Device Authorization flow..."
    local device_resp=$(curl -s -X POST \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "client_id=$CLIENT_ID&scope=$scope" \
        "https://oauth2.googleapis.com/device/code")

    local device_code=$(echo "$device_resp" | jq -r '.device_code')
    local user_code=$(echo "$device_resp" | jq -r '.user_code')
    local verification_url=$(echo "$device_resp" | jq -r '.verification_url')
    local interval=$(echo "$device_resp" | jq -r '.interval // 5')

    if [ "$device_code" = "null" ] || [ -z "$device_code" ]; then
        print_error "Failed to start device flow"
        print_error "Response: $device_resp"
        exit 1
    fi

    echo ""
    print_status "Step 1: Authorize the application"
    print_status "Open this URL: $verification_url"
    print_status "Enter this code when prompted: $user_code"
    echo ""
    if command -v open &> /dev/null; then
        open "$verification_url" || true
    fi

    print_status "Step 2: Waiting for you to complete authorization..."
    while true; do
        sleep "$interval"
        # Include client_secret as Google now requires it for TV & Limited Input Devices clients
        local token_resp=$(curl -s -X POST \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET&device_code=$device_code&grant_type=urn:ietf:params:oauth:grant-type:device_code" \
            "https://oauth2.googleapis.com/token")

        local access_token=$(echo "$token_resp" | jq -r '.access_token')
        local refresh_token=$(echo "$token_resp" | jq -r '.refresh_token')
        local expires_in=$(echo "$token_resp" | jq -r '.expires_in')
        local error=$(echo "$token_resp" | jq -r '.error // empty')

        if [ -n "$access_token" ] && [ "$access_token" != "null" ]; then
            local expires_at=$(( $(date +%s) + expires_in ))
            mkdir -p "$(dirname "$TOKEN_FILE")"
            jq -n \
                --arg access_token "$access_token" \
                --arg refresh_token "$refresh_token" \
                --arg expires_at "$expires_at" \
                '{access_token: $access_token, refresh_token: $refresh_token, expires_at: ($expires_at | tonumber)}' \
                > "$TOKEN_FILE"
            print_status "Tokens saved to $TOKEN_FILE"
            break
        fi

        if [ "$error" = "authorization_pending" ]; then
            continue
        fi
        if [ "$error" = "slow_down" ]; then
            sleep $((interval + 2))
            continue
        fi

        print_error "Device flow failed: $token_resp"
        exit 1
    done
}

# Main setup function
main() {
    print_status "Setting up OAuth2 authentication for Google Sheets API..."
    
    # Check dependencies
    check_dependencies
    
    # Check if credentials are configured
    if [ "$CLIENT_ID" = "YOUR_CLIENT_ID" ] || [ "$CLIENT_SECRET" = "YOUR_CLIENT_SECRET" ]; then
        print_error "Please configure CLIENT_ID and CLIENT_SECRET in this script first"
        print_error "Get these from Google Cloud Console > APIs & Services > Credentials"
        exit 1
    fi
    
    # Start device authorization flow (no redirect URI required)
    start_device_flow
    
    print_status "OAuth2 setup completed successfully!"
    print_status "You can now use the raycast-org-to-sheets-oauth2.sh script"
}

# Run main function
main "$@"
