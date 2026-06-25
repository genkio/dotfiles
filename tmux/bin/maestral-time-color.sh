#!/bin/sh
#
# Tint the status-right clock red while the Maestral (Dropbox) sync daemon is
# down, otherwise emit nothing. Wired into status-right via #() in
# apply-theme.sh, so it re-runs every status-interval. $1 is the active theme's
# attention red (hex, no leading #) - apply-theme.sh owns the palette and the
# light/dark flip, so the red tracks the current theme.

red="${1:-af3029}"

# No maestral on this machine -> stay out of the way, never tint the clock.
command -v maestral >/dev/null 2>&1 || exit 0

# `maestral status` exits 0 when the daemon is up, 1 when it is down
# (it prints "Maestral daemon is not running." then ctx.exit(1)).
maestral status >/dev/null 2>&1 || printf '#[fg=#%s]' "$red"
