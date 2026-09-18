#!/usr/bin/env bash

set -u

window_id="${1-}"
[ -n "$window_id" ] || exit 0
command -v tmux >/dev/null 2>&1 || exit 0

states="$(tmux list-panes -t "$window_id" -F '#{@agent_pane_state}' 2>/dev/null)" || exit 0

attention=0
busy=0
printf '%s\n' "$states" | grep -qx attention && attention=1
printf '%s\n' "$states" | grep -qx busy && busy=1

tmux set-window-option -q -t "$window_id" @agent_attention "$attention" 2>/dev/null
tmux set-window-option -q -t "$window_id" @agent_busy "$busy" 2>/dev/null
exit 0
