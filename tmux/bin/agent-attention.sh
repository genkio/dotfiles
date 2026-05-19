#!/usr/bin/env bash
# Fired by Claude Code's Notification hook, which triggers whenever
# Claude Code surfaces a notification to the user — most importantly,
# permission/approval prompts. Marks the window as awaiting the user's
# attention so the tmux status overlay turns it red.
#
# Clears @agent_busy because the agent is paused, not executing, while
# waiting for the user. Clears @agent_awaiting because "needs approval"
# (red) is a stronger signal than "finished" (green) and should not be
# masked by a stale completion flag.

set -u

[ -n "${TMUX_PANE:-}" ] || exit 0
command -v tmux >/dev/null 2>&1 || exit 0

window_id="$(tmux display-message -p -t "$TMUX_PANE" '#{window_id}' 2>/dev/null)" || exit 0
[ -n "$window_id" ] || exit 0

tmux set-window-option -q -t "$window_id" @agent_attention 1
tmux set-window-option -q -t "$window_id" @agent_busy 0
tmux set-window-option -q -t "$window_id" @agent_awaiting 0
exit 0
