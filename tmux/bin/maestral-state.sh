#!/bin/sh
#
# Report the Maestral (Dropbox) sync daemon as one word for status-usage.sh:
# "error" while it is down or wedged, "sync" while it is transferring, nothing
# when it is idle and clean. status-usage.sh owns the colors and only shows the
# dbx field at all when this prints something, so silence means "stay hidden".

# No maestral on this machine -> stay out of the way, never claim a state.
command -v maestral >/dev/null 2>&1 || exit 0

# `maestral status` exits 0 when the daemon is up, 1 when it is down
# (it prints "Maestral daemon is not running." then ctx.exit(1)). It also exits
# 0 while wedged: a fatal API error leaves Status "Paused" and appends the error
# text, so the status line and the sync-error count both have to be read.
if ! out="$(maestral status 2>/dev/null)"; then
  echo error
  exit 0
fi

status=$(printf '%s\n' "$out" | awk '/^Status/ { $1 = ""; sub(/^ +/, ""); sub(/ +$/, ""); print; exit }')
errors=$(printf '%s\n' "$out" | awk '/^Sync errors/ { print $3; exit }')

case "$status" in
  # wedged, stopped, or reporting a failure: needs a human
  Paused*|Disconnected*|*[Ee]rror*|*failed*|*Failed*) echo error ;;
  Syncing*|Connecting*|Indexing*|Downloading*|Uploading*) echo sync ;;
  *)
    # "Up to date" but files are stuck in the error list
    if [ -n "$errors" ] && [ "$errors" -gt 0 ] 2>/dev/null; then echo error; fi
    ;;
esac

exit 0
