#!/usr/bin/env bash
set -euo pipefail

client_tty=${1:-}
client_termname=${2:-}

selection=$(cat)
[ -z "$selection" ] && exit 0

if [ -z "$client_tty" ]; then
  if command -v tmux >/dev/null 2>&1; then
    client_tty=$(tmux display-message -p '#{client_tty}' 2>/dev/null || true)
  fi

  if [ -z "$client_tty" ] && tty -s; then
    client_tty=$(tty 2>/dev/null || true)
  fi
fi

if [ -z "$client_termname" ] && command -v tmux >/dev/null 2>&1; then
  client_termname=$(tmux display-message -p '#{client_termname}' 2>/dev/null || true)
fi

if [ -n "$client_tty" ] && [ -c "$client_tty" ]; then
  encoded=$(printf -- '%s' "$selection" | base64 | tr -d '\r\n')

  case "$client_termname" in
    tmux* | screen*) printf -- '\033Ptmux;\033\033]52;c;%s\a\033\\' "$encoded" > "$client_tty" ;;
  esac

  printf -- '\033]52;c;%s\a' "$encoded" > "$client_tty"
fi

if [ -z "${SSH_CONNECTION:-}" ]; then
  printf -- '%s' "$selection" | pbcopy
fi
