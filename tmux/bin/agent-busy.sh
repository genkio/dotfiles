#!/usr/bin/env bash
# Fired by Claude Code on UserPromptSubmit, PreToolUse and PostToolUse
# (and Codex equivalents). Marks the agent's window (status overlay)
# and pane (border, via agent-pane-state.sh) as actively working: orange.
#
# PostToolUse is load-bearing for clearing the red "needs approval"
# state. PreToolUse fires BEFORE the permission/elicitation prompt, so
# it cannot clear the red that the prompt then sets. PostToolUse fires
# after the approved tool finishes (and right after an elicitation such
# as AskUserQuestion is answered), flipping red back to orange promptly.
# Without it, red lingered until the next tool's PreToolUse or Stop.

set -u

[ -n "${TMUX_PANE:-}" ] || exit 0
command -v tmux >/dev/null 2>&1 || exit 0

window_id="$(tmux display-message -p -t "$TMUX_PANE" '#{window_id}' 2>/dev/null)" || exit 0
[ -n "$window_id" ] || exit 0

tmux set-window-option -q -t "$window_id" @agent_busy 1
tmux set-window-option -q -t "$window_id" @agent_awaiting 0
tmux set-window-option -q -t "$window_id" @agent_attention 0

# per-pane border: this pane is the one actually working -> orange
"$HOME/dotfiles/tmux/bin/agent-pane-state.sh" busy
exit 0
