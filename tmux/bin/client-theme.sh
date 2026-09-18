#!/usr/bin/env bash
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

PATH="$PATH:/usr/local/bin:/opt/homebrew/bin"

tmux info > /dev/null 2>&1 || exit 0

opt() { tmux show-option -gqv "$1"; }

[ "$(opt @theme_auto_client)" = "on" ] || exit 0

if [ "$event" = "active" ] && [ -n "$event_tty" ] && [ -f "$decider" ]; then
  read -r prev_decider < "$decider" || prev_decider=""
  [ "$prev_decider" != "$event_tty" ] || exit 0
fi

desktop="$(opt @theme_desktop)"
extra=" $(opt @theme_mobile_peers) "

attached_ttys() {
  tmux list-clients 2> /dev/null | sed -n 's/^\([^:]*\):.*/\1/p' | sort -u
}

peer_of() {
  who | awk -v tty="${1#/dev/}" '
    $2 == tty && match($0, /\(([^)]+)\)$/) {
      print substr($0, RSTART + 1, RLENGTH - 2); exit
    }'
}

is_mobile_peer() {
  case "$extra" in *" $1 "*) return 0 ;; esac
  tailscale status 2> /dev/null |
    awk -v peer="$1" 'tolower($1) == tolower(peer) || tolower($2) == tolower(peer) { print tolower($4) }' |
    grep -qE '^(ios|android)$'
}

has_sshd_ancestor() {
  local start pid depth cmd
  for start in $(ps -t "${1#/dev/}" -o pid= 2> /dev/null | tr -d ' '); do
    pid="$start"
    depth=0
    while [ -n "$pid" ] && [ "$pid" -gt 1 ] && [ "$depth" -lt 8 ]; do
      cmd="$(ps -o comm= -p "$pid" 2> /dev/null | tr -d ' ')" || cmd=""
      [ -n "$cmd" ] || break
      case "${cmd##*/}" in sshd | sshd-session) return 0 ;; esac
      pid="$(ps -o ppid= -p "$pid" 2> /dev/null | tr -d ' ')" || pid=""
      depth=$((depth + 1))
    done
  done
  return 1
}

is_mobile_tty() {
  local peer
  has_sshd_ancestor "$1" || return 1
  peer="$(peer_of "$1")"
  [ -n "$peer" ] || return 1
  is_mobile_peer "$peer"
}

read_state() {
  REPLY=""
  [ -f "$1" ] || return 0
  read -r REPLY < "$1" || true
}

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
  chose="$event_tty"
  is_mobile_tty "$event_tty" && mobile=1 || true
else
  read_state "$decider"
  prev="$REPLY"
  if [ -n "$prev" ] && [ "$prev" != "$event_tty" ] && is_attached "$prev"; then
    chose="$prev"
    is_mobile_tty "$prev" && mobile=1 || true
  else
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

"$dotfiles/scripts/apply-theme-all.sh"
