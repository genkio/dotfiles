#!/bin/sh

PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

pkill -x sketchybar
pkill -x borders

sketchybar &

"$(dirname "$0")/reclaim-workspaces.sh"

"$(dirname "$0")/sync.sh" force
