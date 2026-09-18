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
if tmux list-panes -a -F '#{@agent_pane_state}' 2>/dev/null | grep -qx attention; then
  attention="$(aerospace list-windows --all --format '%{app-name}|%{workspace}' \
                 | awk -F'|' '$1 == "Alacritty" { print $2 }' \
                 | sort -u)"
fi

if [ -n "$attention" ]; then
  visible="$(printf '%s\n%s\n' "$occupied" "$attention" | grep . | sort -u)"
else
  visible="$occupied"
  [ "$(printf '%s\n' "$visible" | grep -c .)" -gt 1 ] || visible=""
fi

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
