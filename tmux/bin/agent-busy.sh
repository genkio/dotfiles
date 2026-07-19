#!/usr/bin/env bash
# Fired by Claude Code on UserPromptSubmit, PreToolUse and PostToolUse
# (and Codex equivalents). Marks this agent's pane as actively working:
# orange border. The window-level @agent_attention / @agent_busy flags
# for the status overlay are derived from all panes by
# agent-pane-state.sh, so the window title stays red while a DIFFERENT
# pane in the window is still waiting on the user.
#
# PostToolUse is load-bearing for clearing this pane's red "needs
# approval" state. PreToolUse fires BEFORE the permission/elicitation
# prompt, so it cannot clear the red that the prompt then sets.
# PostToolUse fires after the approved tool finishes (and right after
# an elicitation such as AskUserQuestion is answered), flipping this
# pane back to orange promptly -- and the window title with it, once no
# other pane is stuck.

set -u

[ -n "${TMUX_PANE:-}" ] || exit 0
command -v tmux >/dev/null 2>&1 || exit 0

window_id="$(tmux display-message -p -t "$TMUX_PANE" '#{window_id}' 2>/dev/null)" || exit 0
[ -n "$window_id" ] || exit 0

# new work accepted: the green "finished, come back" title is stale now
tmux set-window-option -q -t "$window_id" @agent_awaiting 0

"$HOME/dotfiles/tmux/bin/agent-pane-state.sh" busy
exit 0
