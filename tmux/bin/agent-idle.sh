#!/usr/bin/env bash
# Fired by Claude Code's Stop hook and Codex's Stop hook.
#
# Pane level: the border turns green (awaiting) so that with several
# agents in one window you can see which panes have finished. Skipped
# only when the user is looking at this exact pane as it stops -- then
# there is nothing to announce and the state just clears. A green
# border is cleared later by the pane-focus-in hook in .tmux.conf (the
# user visited the pane) or by the next prompt (agent-busy.sh).
#
# Window level: @agent_attention / @agent_busy are re-derived from all
# panes by agent-pane-state.sh, so another pane's stuck red survives
# this agent stopping. @agent_awaiting (green title) is set here, and
# only when the user does not appear to be watching the window.
#
# "Watching" is decided in layers:
#   1. On macOS, the terminal app (Alacritty and Apple Terminal by
#      default; configurable via $TMUX_WINDOW_AGENT_TERMINAL_BUNDLES,
#      space-separated bundle ids) must be the frontmost app. If
#      anything else is frontmost, the user is not watching, period
#      -- even if tmux still considers the window active in its session.
#   2. The window must be the active window in some attached tmux
#      client. If the user is on a different tmux window inside the
#      terminal, they are not watching this one either.
#   3. (pane green only) this pane must also be the window's active
#      pane; being on the window but focused elsewhere still earns the
#      finished pane its green border.
#
# On non-macOS systems, layer 1 is treated as always satisfied (back to
# pure tmux semantics).

set -u

[ -n "${TMUX_PANE:-}" ] || exit 0
command -v tmux >/dev/null 2>&1 || exit 0

window_id="$(tmux display-message -p -t "$TMUX_PANE" '#{window_id}' 2>/dev/null)" || exit 0
[ -n "$window_id" ] || exit 0

terminal_is_frontmost() {
  [ "$(uname)" = "Darwin" ] || return 0
  command -v osascript >/dev/null 2>&1 || return 0

  local front bundles b
  front="$(osascript -e 'tell application "System Events" to get bundle identifier of first application process whose frontmost is true' 2>/dev/null)"
  [ -n "$front" ] || return 0

  bundles="${TMUX_WINDOW_AGENT_TERMINAL_BUNDLES:-org.alacritty com.apple.Terminal}"
  for b in $bundles; do
    [ "$front" = "$b" ] && return 0
  done
  return 1
}

window_is_tmux_active() {
  tmux list-clients -F '#{client_session}' 2>/dev/null \
    | sort -u \
    | while read -r sess; do
        [ -n "$sess" ] || continue
        active="$(tmux display-message -p -t "$sess" '#{window_id}' 2>/dev/null)"
        [ "$active" = "$window_id" ] && { echo yes; break; }
      done | grep -q yes
}

pane_is_active() {
  [ "$(tmux display-message -p -t "$TMUX_PANE" '#{pane_active}' 2>/dev/null)" = "1" ]
}

if terminal_is_frontmost && window_is_tmux_active; then
  # user is on this window: no green title. Pane border still goes
  # green unless they are focused on this very pane.
  if pane_is_active; then
    "$HOME/dotfiles/tmux/bin/agent-pane-state.sh" ""
  else
    "$HOME/dotfiles/tmux/bin/agent-pane-state.sh" awaiting
  fi
  exit 0
fi

# set the title flag before the pane state so the refresh-client inside
# agent-pane-state.sh repaints the green title too
tmux set-window-option -q -t "$window_id" @agent_awaiting 1
"$HOME/dotfiles/tmux/bin/agent-pane-state.sh" awaiting
exit 0
