#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Emacs Everywhere
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 💻

# Documentation:
# @raycast.description Keyboard shortcut to run Emacs Everywhere
# @raycast.author notkylespink
# @raycast.authorURL https://raycast.com/notkylespink

emacsclient --eval "(progn (emacs-everywhere) (with-current-buffer (current-buffer) (erase-buffer)))"

