#!/bin/sh

# Push the workspace indicator's state into sketchybar: the focused workspace,
# which workspaces are worth a number at all - the ones holding windows, plus
# the focused one even when empty, so a switch to an empty workspace still
# highlights something - and which of them hold an agent waiting on the user.
# One workspace in use needs no indicator, so the list goes empty and the whole
# thing disappears.
#
# The memo keeps a focus change that changed nothing from re-running an item
# script per workspace. `force` is for sketchybarrc, whose fresh items have to
# be painted whatever a past session left in the memo.

PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

MEMO="${TMPDIR:-/tmp}/aerospace-spaces-state"

focused="$(aerospace list-workspaces --focused)"
occupied="$(
  { aerospace list-workspaces --monitor all --empty no; printf '%s\n' "$focused"; } \
    | sort -u
)"

# A Claude Code or pi agent asking for input marks its tmux pane (see
# tmux/bin/agent-attention.sh), and the terminal hosting that pane is what puts
# it on a workspace. Alacritty by name because that is the terminal this repo
# configures; a pane in any other one is simply not found.
attention=""
if tmux list-panes -a -F '#{@agent_pane_state}' 2>/dev/null | grep -qx attention; then
  attention="$(aerospace list-windows --all --format '%{app-name}|%{workspace}' \
                 | awk -F'|' '$1 == "Alacritty" { print $2 }' \
                 | sort -u)"
fi

if [ -n "$attention" ]; then
  # A waiting agent outranks the tidiness rule below: the box has to be there
  # to be red, even when it would be the only one.
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
