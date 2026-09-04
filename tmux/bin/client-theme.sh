#!/usr/bin/env bash
#
# Pick the theme from the client you are actually sitting at: the one that most
# recently attached or was used decides. Mobile SSH client -> dark, anything
# else -> the desktop default (@theme_desktop). Driven by the client-attached /
# client-detached / client-active / client-focus-in hooks in .tmux.conf.
#
# Last-used rather than any-mobile-wins because a phone SSH app keeps its client
# attached in the background: the session would stay dark for days after you put
# the phone down. Attaching is too weak a signal on its own for the same reason -
# with a live connection sitting open on every device you rarely attach at all -
# so typing on a client (client-active) or focusing its terminal hands it the
# decision too.
#
# The deciding client is remembered in $XDG_CACHE_HOME/dotfiles/theme-client.
# While it is still attached its verdict stands, so an unrelated client leaving
# can't hand the decision to a phone nobody is holding. Once the decider itself
# goes, the remaining clients are rescanned, preferring a desktop one: a phone
# wins a rescan only when it is the last client standing.
#
# A client is "mobile" when its login tty came in over SSH (`who` prints the
# peer) and that peer is an iOS/Android node in `tailscale status`, or is listed
# in @theme_mobile_peers (ip or hostname) for clients off the tailnet.
#
# tmux colours are server-global, so this is a whole-session flip, not a
# per-client one: the phone taking over repaints the Mac too. prefix+t still
# flips manually and holds until another client takes the decision, so a manual
# choice survives you carrying on typing at the same client.
#
# Usage:
#   client-theme.sh --attached <tty>   that client just attached and now decides
#   client-theme.sh --active <tty>     that client was just used; no-op if it is
#                                      already the decider (the common case, so
#                                      this stays cheap on a per-keystroke hook)
#   client-theme.sh --detached <tty>   that client left; re-decide if it decided
#   client-theme.sh                    re-decide from the attached clients

set -euo pipefail

event=""
event_tty=""
case "${1:-}" in
  --attached | --detached | --active)
    event="${1#--}"
    event_tty="${2:-}"
    ;;
esac

dotfiles="${DOTFILES_DIR:-$HOME/dotfiles}"
state_dir="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles"
override="$state_dir/theme-override"
decider="$state_dir/theme-client"

# tmux hooks inherit the server's env, which can predate a PATH that has the
# tailscale CLI on it.
PATH="$PATH:/usr/local/bin:/opt/homebrew/bin"

tmux info > /dev/null 2>&1 || exit 0

opt() { tmux show-option -gqv "$1"; }

[ "$(opt @theme_auto_client)" = "on" ] || exit 0

# client-active / client-focus-in fire whenever you switch which client you are
# using, which is far more often than an attach. When the client being used
# already holds the decision - the common case, every keystroke after the first -
# there is nothing to recompute, so bail before spawning who/tailscale and
# repainting every tty. This is also what lets a manual prefix+t survive: it
# holds until a DIFFERENT client takes the decision.
if [ "$event" = "active" ] && [ -n "$event_tty" ] && [ -f "$decider" ]; then
  read -r prev_decider < "$decider" || prev_decider=""
  [ "$prev_decider" != "$event_tty" ] || exit 0
fi

desktop="$(opt @theme_desktop)"
extra=" $(opt @theme_mobile_peers) "

# Every attached client's tty. No -F: this runs under run-shell, where a
# #{client_tty} format is expanded against the CALLING client, so every row would
# collapse to the tty of whoever triggered the hook and a phone still attached
# elsewhere would go unseen. The default output leads each row with the real tty,
# and a tty path never contains a colon.
attached_ttys() {
  tmux list-clients 2> /dev/null | sed -n 's/^\([^:]*\):.*/\1/p' | sort -u
}

# Peer host/ip the given tty logged in from; empty for a local login.
peer_of() {
  who | awk -v tty="${1#/dev/}" '
    $2 == tty && match($0, /\(([^)]+)\)$/) {
      print substr($0, RSTART + 1, RLENGTH - 2); exit
    }'
}

is_mobile_peer() {
  case "$extra" in *" $1 "*) return 0 ;; esac
  # tailscale status columns: ip host user os state
  tailscale status 2> /dev/null |
    awk -v peer="$1" 'tolower($1) == tolower(peer) || tolower($2) == tolower(peer) { print tolower($4) }' |
    grep -qE '^(ios|android)$'
}

is_mobile_tty() {
  local peer
  peer="$(peer_of "$1")"
  [ -n "$peer" ] || return 1
  is_mobile_peer "$peer"
}

read_state() {
  REPLY=""
  [ -f "$1" ] || return 0
  read -r REPLY < "$1" || true
}

# Snapshot the client list once, and test membership with `case` rather than a
# pipe into grep -q: -q exits on the first match, and under `set -o pipefail`
# the resulting EPIPE upstream would read as a failed test.
attached="$(attached_ttys)"
is_attached() {
  case $'\n'"$attached"$'\n' in
    *$'\n'"$1"$'\n'*) return 0 ;;
  esac
  return 1
}

mobile=0
chose=""

if { [ "$event" = "attached" ] || [ "$event" = "active" ]; } && [ -n "$event_tty" ]; then
  # Whoever just sat down, or just typed, decides - full stop.
  chose="$event_tty"
  is_mobile_tty "$event_tty" && mobile=1 || true
else
  # A detach only re-opens the decision if the client that made it is the one
  # leaving; otherwise the standing verdict holds and we just repaint.
  read_state "$decider"
  prev="$REPLY"
  if [ -n "$prev" ] && [ "$prev" != "$event_tty" ] && is_attached "$prev"; then
    chose="$prev"
    is_mobile_tty "$prev" && mobile=1 || true
  else
    # Rescan, preferring a desktop client. A phone lurking in the background
    # must not inherit the decision just because some unrelated local window
    # closed; it only wins here when it is all that is left.
    lurking_mobile=""
    while IFS= read -r tty; do
      [ -n "$tty" ] || continue
      [ "$tty" != "$event_tty" ] || continue
      if is_mobile_tty "$tty"; then
        [ -n "$lurking_mobile" ] || lurking_mobile="$tty"
      else
        chose="$tty"
        break
      fi
    done <<< "$attached"
    if [ -z "$chose" ] && [ -n "$lurking_mobile" ]; then
      chose="$lurking_mobile"
      mobile=1
    fi
  fi
fi

if [ "$mobile" = 1 ]; then
  desired=dark
else
  case "$desktop" in
    dark) desired=dark ;;
    # follow macOS appearance: drop the override entirely
    auto) desired="" ;;
    *) desired=light ;;
  esac
fi

mkdir -p "$state_dir"
printf '%s\n' "$chose" > "$decider"

read_state "$override"
if [ "$REPLY" != "$desired" ]; then
  if [ -z "$desired" ]; then
    rm -f "$override"
  else
    printf '%s\n' "$desired" > "$override"
  fi
fi

# Re-apply even when the file already said the right thing. The OSC repaint only
# reaches ttys attached AT THE TIME of a flip, so a client that was away for one
# (the Mac while the phone was on) comes back painted with the old palette: its
# tmux and nvim are light, its Alacritty is still dark. Attaching has to repaint,
# not just agree with the file. Idempotent, so the extra run costs nothing.
"$dotfiles/scripts/apply-theme-all.sh"
