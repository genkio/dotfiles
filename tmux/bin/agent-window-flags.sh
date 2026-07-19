#!/usr/bin/env bash
# Recompute a window's @agent_attention / @agent_busy flags from the
# @agent_pane_state of every pane in it: red if ANY pane is waiting on
# the user, orange if ANY pane is working. Deriving the flags from pane
# states (instead of letting each hook write them directly) is what
# makes red sticky with several agents in one window: a neighbour's
# busy/idle fires can no longer clobber a stuck pane's attention flag.
# Red clears only when the stuck pane itself transitions -- the user
# responds, stops the agent, or kills the pane.
#
# Called by agent-pane-state.sh on every pane state transition, and by
# the pane-death hooks in .tmux.conf so a killed agent pane cannot
# leave a stale red/orange title behind.
#
# @agent_awaiting (green title) is NOT derived here: it keeps its
# "finished while you were not watching" semantics, owned by
# agent-idle.sh and cleared by session-window-changed / agent-busy.sh.

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
