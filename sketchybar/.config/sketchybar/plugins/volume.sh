#!/bin/sh

if [ "$SENDER" = "volume_change" ]; then
  volume="$INFO"
else
  volume="$(osascript -e 'set settings to (get volume settings)
    if output muted of settings then return 0
    return output volume of settings' 2>/dev/null)"
fi

if [ "${volume:-0}" -eq 0 ] 2>/dev/null; then
  sketchybar --set "$NAME" drawing=off
else
  sketchybar --set "$NAME" drawing=on label="$volume%"
fi
