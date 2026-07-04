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
# (it prints "Maestral daemon is not running." then ctx.exit(1)).
if ! out="$(maestral status 2>/dev/null)"; then
  printf '#[fg=#%s]' "$red"
elif printf '%s' "$out" | grep -q '^Status.*Syncing'; then
  printf '#[fg=#%s]' "$yellow"
fi
