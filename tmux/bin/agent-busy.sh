#!/usr/bin/env bash
# Fired by Claude Code's UserPromptSubmit hook and Codex's
# UserPromptSubmit hook. Marks the window containing the agent's tmux
# pane as actively working, so tmux-window-agent's status-format
# overlay turns it orange.

set -u

[ -n "${TMUX_PANE:-}" ] || exit 0
command -v tmux >/dev/null 2>&1 || exit 0

window_id="$(tmux display-message -p -t "$TMUX_PANE" '#{window_id}' 2>/dev/null)" || exit 0
[ -n "$window_id" ] || exit 0

tmux set-window-option -q -t "$window_id" @agent_busy 1
tmux set-window-option -q -t "$window_id" @agent_awaiting 0
tmux set-window-option -q -t "$window_id" @agent_attention 0
exit 0
