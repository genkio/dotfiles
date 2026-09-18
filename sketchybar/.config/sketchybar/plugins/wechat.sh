#!/bin/sh

badge="$(osascript -e 'tell application "System Events" to tell process "Dock" \
  to get value of attribute "AXStatusLabel" of UI element "WeChat" of list 1' \
  2>/dev/null)"

case "$badge" in
  "" | "missing value")
    sketchybar --set "$NAME" drawing=off
    ;;
  *)
    sketchybar --set "$NAME" drawing=on label="hey"
    ;;
esac
