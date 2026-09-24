#!/bin/sh

# Workspace pills already show the Mail badge under AeroSpace.
# Check Mail is running first: asking for the unread count would launch it.
if pgrep -x AeroSpace >/dev/null || ! pgrep -x Mail >/dev/null; then
  sketchybar --set "$NAME" drawing=off
  exit 0
fi

unread="$(osascript -e 'with timeout of 3 seconds
  tell application "Mail" to get unread count of inbox
end timeout' 2>/dev/null)"

case "$unread" in
  "" | 0) sketchybar --set "$NAME" drawing=off ;;
  *)      sketchybar --set "$NAME" drawing=on label="Mail ($unread)" ;;
esac
