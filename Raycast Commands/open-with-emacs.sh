#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Open with Emacs
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 💻

# Documentation:
# @raycast.description Opens selected file or focused folder in Emacs
# @raycast.author notkylespink
# @raycast.authorURL https://raycast.com/notkylespink

# Use AppleScript to get the selected Finder item (or front window if nothing is selected)
path=$(osascript <<'EOF'
tell application "Finder"
    set theSelection to selection
    if theSelection is {} then
        try
            set theTarget to (target of front window) as alias
            POSIX path of theTarget
        on error
            POSIX path of (path to home folder)
        end try
    else
        POSIX path of (item 1 of theSelection as alias)
    end if
end tell
EOF
)

# Open the path in Emacs
emacsclient -n "$path" &