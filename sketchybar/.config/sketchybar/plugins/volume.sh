#!/bin/sh

# The volume_change event supplies the current percentage in $INFO, and reports
# 0 for muted as well as for zero - one test covers both, no separate mute
# query. Silence is the state worth no space on the bar.
#
# Any other sender is the startup update, which carries no level, so ask for it.

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
