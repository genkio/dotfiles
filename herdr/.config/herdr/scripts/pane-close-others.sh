#!/bin/sh
set -eu

herdr="${HERDR_BIN_PATH:-herdr}"
pane="${HERDR_ACTIVE_PANE_ID:-}"
[ -n "$pane" ] || { echo "no active pane" >&2; exit 1; }

others=$("$herdr" pane layout --pane "$pane" \
  | jq -r --arg keep "$pane" '.result.layout.panes[].pane_id | select(. != $keep)')
[ -n "$others" ] || exit 0

printf 'close %s other pane(s), keep %s? [y/N] ' "$(printf '%s\n' "$others" | wc -l | tr -d ' ')" "$pane"
read -r reply
case "$reply" in
  [yY]*) ;;
  *) exit 0 ;;
esac

for p in $others; do
  "$herdr" pane close "$p" >/dev/null || true
done
