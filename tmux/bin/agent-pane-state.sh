#!/usr/bin/env bash

set -u

new="${1-}"
[ -n "${TMUX_PANE:-}" ] || exit 0
command -v tmux >/dev/null 2>&1 || exit 0

prev="$(tmux show-option -p -v -t "$TMUX_PANE" @agent_pane_state 2>/dev/null || true)"
tmux set-option -p -q -t "$TMUX_PANE" @agent_pane_state "$new"

[ "$prev" = "$new" ] && exit 0

window_id="$(tmux display-message -p -t "$TMUX_PANE" '#{window_id}' 2>/dev/null)" || exit 0
[ -n "$window_id" ] || exit 0
"$HOME/dotfiles/tmux/bin/agent-window-flags.sh" "$window_id"

sess="$(tmux display-message -p -t "$TMUX_PANE" '#{session_name}' 2>/dev/null)" || exit 0
[ -n "$sess" ] || exit 0
tmux list-clients -t "$sess" -F '#{client_name}' 2>/dev/null | while read -r c; do
  [ -n "$c" ] && tmux refresh-client -t "$c"
done
exit 0
