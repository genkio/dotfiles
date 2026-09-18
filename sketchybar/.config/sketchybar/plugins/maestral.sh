#!/bin/sh

PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

RED=0xfff7768e
YELLOW=0xffe0af68

command -v maestral >/dev/null 2>&1 || {
  sketchybar --set "$NAME" drawing=off
  exit 0
}

if ! out="$(maestral status 2>/dev/null)"; then
  sketchybar --set "$NAME" drawing=on label.color="$RED" label="B"
  exit 0
fi

status=$(printf '%s\n' "$out" | awk '/^Status/ { $1 = ""; sub(/^ +/, ""); sub(/ +$/, ""); print; exit }')
errors=$(printf '%s\n' "$out" | awk '/^Sync errors/ { print $3; exit }')

case "$status" in
  Paused*|Disconnected*|*[Ee]rror*|*failed*|*Failed*)
    sketchybar --set "$NAME" drawing=on label.color="$RED" label="B"
    ;;
  Syncing*|Connecting*|Indexing*|Downloading*|Uploading*)
    sketchybar --set "$NAME" drawing=on label.color="$YELLOW" label="B"
    ;;
  *)
    if [ -n "$errors" ] && [ "$errors" -gt 0 ] 2>/dev/null; then
      sketchybar --set "$NAME" drawing=on label.color="$RED" label="B"
    else
      sketchybar --set "$NAME" drawing=off
    fi
    ;;
esac
