#!/bin/sh
#
# Emit a tmux color for the Maestral (Dropbox) sync daemon: red while it is
# down, yellow while it is syncing, nothing otherwise. Called by status-usage.sh
# to tint the RAM number, alongside the left block's other conditional colors.
# $1/$2 are the active theme's attention red / busy yellow (hex, no leading #)
# - apply-theme.sh owns the palette and the light/dark flip, so the colors
# track the current theme.

red="${1:-af3029}"
yellow="${2:-ad8301}"

# No maestral on this machine -> stay out of the way, never tint anything.
command -v maestral >/dev/null 2>&1 || exit 0

# `maestral status` exits 0 when the daemon is up, 1 when it is down
# (it prints "Maestral daemon is not running." then ctx.exit(1)). It also exits
# 0 while wedged: a fatal API error leaves Status "Paused" and appends the error
# text, so the status line and the sync-error count both have to be read.
if ! out="$(maestral status 2>/dev/null)"; then
  printf '#[fg=#%s]' "$red"
  exit 0
fi

status=$(printf '%s\n' "$out" | awk '/^Status/ { $1 = ""; sub(/^ +/, ""); sub(/ +$/, ""); print; exit }')
errors=$(printf '%s\n' "$out" | awk '/^Sync errors/ { print $3; exit }')

case "$status" in
  # wedged, stopped, or reporting a failure: needs a human
  Paused*|Disconnected*|*[Ee]rror*|*failed*|*Failed*) printf '#[fg=#%s]' "$red" ;;
  Syncing*|Connecting*|Indexing*|Downloading*|Uploading*) printf '#[fg=#%s]' "$yellow" ;;
  *)
    # "Up to date" but files are stuck in the error list
    [ -n "$errors" ] && [ "$errors" -gt 0 ] 2>/dev/null && printf '#[fg=#%s]' "$red"
    ;;
esac
