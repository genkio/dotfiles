#!/bin/sh

PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

MEMO="${TMPDIR:-/tmp}/aerospace-spaces-state"

focused="$(aerospace list-workspaces --focused)"
occupied="$(
  { aerospace list-workspaces --monitor all --empty no
    aerospace list-workspaces --monitor all --visible
    printf '%s\n' "$focused"; } | sort -u
)"

attention=""

visible="$occupied"
[ "$(printf '%s\n' "$visible" | grep -c .)" -gt 1 ] || visible=""

visible="$(printf '%s' "$visible" | paste -sd, -)"
attention="$(printf '%s' "$attention" | paste -sd, -)"

state="$focused|$visible|$attention"
if [ "$1" != force ] && [ "$(cat "$MEMO" 2>/dev/null)" = "$state" ]; then
  exit 0
fi

sketchybar --trigger aerospace_workspace_change \
           FOCUSED_WORKSPACE="$focused" \
           VISIBLE_WORKSPACES="$visible" \
           ATTENTION_WORKSPACES="$attention"

printf '%s' "$state" > "$MEMO"
