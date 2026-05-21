#!/usr/bin/env bash
# Fired by Claude Code and Codex on UserPromptSubmit and PreToolUse.
# Marks the window containing the agent's tmux pane as actively
# working, so the status-format overlay turns it orange.
#
# PreToolUse coverage is what transitions the window out of the red
# "needs approval" state once the user has approved a permission
# prompt and the tool actually starts running — without it, red would
# stay until the entire turn ended.

set -u

[ -n "${TMUX_PANE:-}" ] || exit 0
command -v tmux >/dev/null 2>&1 || exit 0

window_id="$(tmux display-message -p -t "$TMUX_PANE" '#{window_id}' 2>/dev/null)" || exit 0
[ -n "$window_id" ] || exit 0

tmux set-window-option -q -t "$window_id" @agent_busy 1
tmux set-window-option -q -t "$window_id" @agent_awaiting 0
tmux set-window-option -q -t "$window_id" @agent_attention 0
exit 0
