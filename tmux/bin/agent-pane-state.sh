#!/usr/bin/env bash
# Set the agent border state for the pane the agent runs in ($TMUX_PANE),
# then re-derive the window-level @agent_attention / @agent_busy flags
# from ALL panes in the window (agent-window-flags.sh). The callers
# (agent-{busy,attention,idle}.sh) no longer write those two window
# options themselves: derived flags mean one stuck agent keeps the
# window title red even while neighbour agents keep firing busy/idle
# hooks -- last-writer-wins used to mask the red. @agent_awaiting stays
# caller-owned: green depends on whether the user was watching, which
# only agent-idle.sh knows.
#
# Arg 1 -- new state, one of:
#   busy       border turns orange (agent actively working in this pane)
#   attention  border turns red    (agent needs the user's approval)
#   awaiting   border turns green  (agent finished; cleared when the
#              user focuses the pane -- pane-focus-in hook -- or on the
#              next prompt)
#   ""         clear; border returns to its theme default
#
# apply-theme.sh wires @agent_pane_state into pane-border-style /
# pane-active-border-style, so this script only sets options and nudges
# a redraw -- the palette stays in one place and tracks light/dark.

set -u

new="${1-}"
[ -n "${TMUX_PANE:-}" ] || exit 0
command -v tmux >/dev/null 2>&1 || exit 0

prev="$(tmux show-option -p -v -t "$TMUX_PANE" @agent_pane_state 2>/dev/null || true)"
tmux set-option -p -q -t "$TMUX_PANE" @agent_pane_state "$new"

# No transition -> border and window flags are both already right.
# Skips the recompute/redraw on the many back-to-back busy fires
# (UserPromptSubmit + every PreToolUse) within one turn.
[ "$prev" = "$new" ] && exit 0

window_id="$(tmux display-message -p -t "$TMUX_PANE" '#{window_id}' 2>/dev/null)" || exit 0
[ -n "$window_id" ] || exit 0
"$HOME/dotfiles/tmux/bin/agent-window-flags.sh" "$window_id"

# Setting an option does not repaint borders on its own. Refresh every
# client viewing this pane's session so the new colour shows promptly.
sess="$(tmux display-message -p -t "$TMUX_PANE" '#{session_name}' 2>/dev/null)" || exit 0
[ -n "$sess" ] || exit 0
tmux list-clients -t "$sess" -F '#{client_name}' 2>/dev/null | while read -r c; do
  [ -n "$c" ] && tmux refresh-client -t "$c"
done
exit 0
