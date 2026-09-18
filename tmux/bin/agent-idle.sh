#!/usr/bin/env bash

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
  if pane_is_active; then
    "$HOME/dotfiles/tmux/bin/agent-pane-state.sh" ""
  else
    "$HOME/dotfiles/tmux/bin/agent-pane-state.sh" awaiting
  fi
  exit 0
fi

tmux set-window-option -q -t "$window_id" @agent_awaiting 1
"$HOME/dotfiles/tmux/bin/agent-pane-state.sh" awaiting
exit 0
