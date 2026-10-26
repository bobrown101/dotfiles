#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Restart Raycast
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🔄
# @raycast.packageName Raycast

nohup bash -c 'sleep 0.5; osascript -e "quit app \"Raycast\""; sleep 1.5; killall Raycast 2>/dev/null; sleep 0.5; open -a Raycast' >/dev/null 2>&1 &
disown
