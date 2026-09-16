#!/bin/sh

# WeChat's unread count, which it publishes exactly once: as the badge on its
# Dock tile. There is no API for another app's badge, so this asks the Dock
# itself through the accessibility API. `missing value` is the answer when there
# is no badge, and `Can't get UI element` when WeChat is neither running nor
# pinned - both mean nothing to show.
#
# Cheap enough at this interval, but it is an AppleEvent round trip, not a file
# read: do not be tempted to poll it every second.

badge="$(osascript -e 'tell application "System Events" to tell process "Dock" \
  to get value of attribute "AXStatusLabel" of UI element "WeChat" of list 1' \
  2>/dev/null)"

case "$badge" in
  "" | "missing value")
    sketchybar --set "$NAME" drawing=off
    ;;
  *)
    # The count is on the Dock tile already; here the only question is whether
    # anyone wants you.
    sketchybar --set "$NAME" drawing=on label="hey"
    ;;
esac
