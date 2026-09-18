#!/usr/bin/env bash

set -u

[ -n "${TMUX_PANE:-}" ] || exit 0
command -v tmux >/dev/null 2>&1 || exit 0

window_id="$(tmux display-message -p -t "$TMUX_PANE" '#{window_id}' 2>/dev/null)" || exit 0
[ -n "$window_id" ] || exit 0

tmux set-window-option -q -t "$window_id" @agent_awaiting 0

"$HOME/dotfiles/tmux/bin/agent-pane-state.sh" busy
exit 0
