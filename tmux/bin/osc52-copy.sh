#!/usr/bin/env bash
set -euo pipefail

client_tty=${1:-}

# Capture selection from stdin
selection=$(cat)
[ -z "$selection" ] && exit 0

# Auto-detect the target TTY when not provided (useful from tools that clear TMUX env)
if [ -z "$client_tty" ]; then
  if command -v tmux >/dev/null 2>&1; then
    client_tty=$(tmux display-message -p '#{client_tty}' 2>/dev/null || true)
  fi

  if [ -z "$client_tty" ] && tty -s; then
    client_tty=$(tty 2>/dev/null || true)
  fi
fi

# Send OSC52 to the tmux client if we have its TTY
if [ -n "$client_tty" ] && [ -c "$client_tty" ]; then
  encoded=$(printf -- '%s' "$selection" | base64 | tr -d '\r\n')
  printf -- '\033]52;c;%s\a' "$encoded" > "$client_tty"
fi

# Mirror to pbcopy only when running locally
if [ -z "${SSH_CONNECTION:-}" ] && command -v pbcopy >/dev/null 2>&1; then
  printf -- '%s' "$selection" | pbcopy
fi
