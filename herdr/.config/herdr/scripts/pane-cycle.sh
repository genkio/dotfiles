#!/bin/sh
set -eu

case "${1:-}" in
  up) back=down ;;
  down) back=up ;;
  left) back=right ;;
  right) back=left ;;
  *) echo "usage: $(basename "$0") up|down|left|right" >&2; exit 2 ;;
esac
dir="$1"

herdr="${HERDR_BIN_PATH:-herdr}"
pane="${HERDR_ACTIVE_PANE_ID:-}"

focus() {
  if [ -n "$1" ]; then
    out=$("$herdr" pane focus --pane "$1" --direction "$2" 2>/dev/null) || return 1
  else
    out=$("$herdr" pane focus --current --direction "$2" 2>/dev/null) || return 1
  fi
  case "$out" in
    *'"changed":true'*) ;;
    *) return 1 ;;
  esac
  printf '%s' "$out" | sed -n 's/.*"focus":{[^}]*"focused_pane_id":"\([^"]*\)".*/\1/p'
}

focus "$pane" "$dir" >/dev/null && exit 0

while next=$(focus "$pane" "$back"); do
  pane="$next"
  [ -n "$pane" ] || break
done
exit 0
