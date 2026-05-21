#!/usr/bin/env bash
# Fired by Claude Code's Notification hook (filtered via matcher to
# permission_prompt | elicitation_dialog) and Codex's PermissionRequest
# hook. Marks the window as awaiting the user's input on something the
# agent cannot proceed without, so the tmux status overlay turns red.
#
# The Notification matcher filter is load-bearing: without it, Claude
# Code's idle_prompt (fired after the agent finishes and the user
# hasn't yet responded) would set red on top of the green that Stop
# just set, making finished windows look like they need approval.
#
# Clears @agent_busy because the agent is paused, not executing, while
# waiting for the user. Clears @agent_awaiting because "needs input"
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
