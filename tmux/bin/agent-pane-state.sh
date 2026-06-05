#!/usr/bin/env bash
# Set the agent border state for the pane the agent runs in ($TMUX_PANE)
# and redraw if it changed. This is the per-pane companion to the
# per-window @agent_* overlay: the caller (agent-{busy,attention,idle}.sh)
# still sets the window options for the status bar; this sets the pane
# option that colours that one pane's border.
#
# Arg 1 -- new state, one of:
#   busy       border turns orange (agent actively working in this pane)
#   attention  border turns red    (agent needs the user's approval)
#   ""         clear; border returns to its theme default
#
# Only busy/attention colour the border. There is no "awaiting" (done)
# border: tmux only draws borders for panes in the currently displayed
# window, and idle.sh only flags awaiting when the user is NOT watching,
# so an awaiting border could never be seen before it went stale. The
# green "finished, come back" signal lives in the window-status overlay.
#
# apply-theme.sh wires @agent_pane_state into pane-border-style /
# pane-active-border-style, so this script only sets the option and nudges
# a redraw -- the palette stays in one place and tracks light/dark.

set -u

new="${1-}"
[ -n "${TMUX_PANE:-}" ] || exit 0
command -v tmux >/dev/null 2>&1 || exit 0

prev="$(tmux show-option -p -v -t "$TMUX_PANE" @agent_pane_state 2>/dev/null || true)"
tmux set-option -p -q -t "$TMUX_PANE" @agent_pane_state "$new"

# No transition -> nothing to repaint. Skips the redraw on the many
# back-to-back busy fires (UserPromptSubmit + every PreToolUse) within
# one turn; the redraw only runs on actual state changes.
[ "$prev" = "$new" ] && exit 0

# Setting an option does not repaint borders on its own. Refresh every
# client viewing this pane's session so the new colour shows promptly.
sess="$(tmux display-message -p -t "$TMUX_PANE" '#{session_name}' 2>/dev/null)" || exit 0
[ -n "$sess" ] || exit 0
tmux list-clients -t "$sess" -F '#{client_name}' 2>/dev/null | while read -r c; do
  [ -n "$c" ] && tmux refresh-client -t "$c"
done
exit 0
