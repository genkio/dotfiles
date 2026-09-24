#!/bin/sh

PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

MEMO="${TMPDIR:-/tmp}/aerospace-running"

if pgrep -x AeroSpace >/dev/null; then
  running=on
else
  running=off
fi

last="$(cat "$MEMO" 2>/dev/null)"
printf '%s' "$running" > "$MEMO"

if [ "$SENDER" = routine ] && [ "$running" = "$last" ]; then
  [ "$running" = on ] && exec "$HOME/.config/aerospace/scripts/spaces-sync.sh"
  exit 0
fi

if [ "$running" = on ]; then
  sketchybar --set quit drawing=on
  exec "$HOME/.config/aerospace/scripts/sync.sh" force
fi

sketchybar --set quit drawing=off \
           --bar hidden=off display=all \
           --trigger aerospace_workspace_change
