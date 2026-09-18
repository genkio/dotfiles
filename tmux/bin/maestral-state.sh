#!/bin/sh

command -v maestral >/dev/null 2>&1 || exit 0

if ! out="$(maestral status 2>/dev/null)"; then
  echo error
  exit 0
fi

status=$(printf '%s\n' "$out" | awk '/^Status/ { $1 = ""; sub(/^ +/, ""); sub(/ +$/, ""); print; exit }')
errors=$(printf '%s\n' "$out" | awk '/^Sync errors/ { print $3; exit }')

case "$status" in
  Paused*|Disconnected*|*[Ee]rror*|*failed*|*Failed*) echo error ;;
  Syncing*|Connecting*|Indexing*|Downloading*|Uploading*) echo sync ;;
  *)
    if [ -n "$errors" ] && [ "$errors" -gt 0 ] 2>/dev/null; then echo error; fi
    ;;
esac

exit 0
