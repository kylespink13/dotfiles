#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Emacs Agenda
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 💻

# Documentation:
# @raycast.description Opens window showing Emacs Agenda
# @raycast.author notkylespink
# @raycast.authorURL https://raycast.com/notkylespink
# @raycast.authorURL https://micro.kennard.uk

emacsclient -e "(progn (my-show-agenda) (with-current-buffer (window-buffer) (setq truncate-lines nil)))" 