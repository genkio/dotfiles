#!/usr/bin/env bash
# Fired by Claude Code's Stop hook and Codex's Stop hook. Marks the
# window as no longer busy. If the user does not currently appear to
# be watching the window, also sets @agent_awaiting so the window
# turns red until the user comes back to it.
#
# "Watching" is decided in two layers:
#   1. On macOS, the terminal app (Ghostty by default; configurable via
#      $TMUX_WINDOW_AGENT_TERMINAL_BUNDLES) must be the frontmost app.
#      If anything else is frontmost, the user is not watching, period
#      — even if tmux still considers the window active in its session.
#   2. The window must be the active window in some attached tmux
#      client. If the user is on a different tmux window inside the
#      terminal, they are not watching this one either.
#
# Both must be true to *skip* setting awaiting. On non-macOS systems,
# layer 1 is treated as always satisfied (back to pure tmux semantics).

set -u

[ -n "${TMUX_PANE:-}" ] || exit 0
command -v tmux >/dev/null 2>&1 || exit 0

window_id="$(tmux display-message -p -t "$TMUX_PANE" '#{window_id}' 2>/dev/null)" || exit 0
[ -n "$window_id" ] || exit 0

tmux set-window-option -q -t "$window_id" @agent_busy 0

terminal_is_frontmost() {
  [ "$(uname)" = "Darwin" ] || return 0
  command -v osascript >/dev/null 2>&1 || return 0

  local front bundles b
  front="$(osascript -e 'tell application "System Events" to get bundle identifier of first application process whose frontmost is true' 2>/dev/null)"
  [ -n "$front" ] || return 0

  bundles="${TMUX_WINDOW_AGENT_TERMINAL_BUNDLES:-com.mitchellh.ghostty}"
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

if terminal_is_frontmost && window_is_tmux_active; then
  exit 0
fi

tmux set-window-option -q -t "$window_id" @agent_awaiting 1
exit 0
