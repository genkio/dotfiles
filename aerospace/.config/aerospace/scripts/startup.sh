#!/bin/sh

PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

pkill -x borders

"$(dirname "$0")/reclaim-workspaces.sh"

sketchybar --trigger aerospace_state_change
