#!/usr/bin/env bash
set -euo pipefail

client_tty=${1:-}
client_termname=${2:-}

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

if [ -z "$client_termname" ] && command -v tmux >/dev/null 2>&1; then
  client_termname=$(tmux display-message -p '#{client_termname}' 2>/dev/null || true)
fi

# Send OSC52 to the tmux client if we have its TTY
if [ -n "$client_tty" ] && [ -c "$client_tty" ]; then
  encoded=$(printf -- '%s' "$selection" | base64 | tr -d '\r\n')

  # If the tmux client is another tmux/screen, also send tmux passthrough.
  # The outer tmux must have allow-passthrough enabled; raw OSC52 stays as a
  # fallback for terminals or tmux configs that accept clipboard sequences.
  case "$client_termname" in
    tmux* | screen*) printf -- '\033Ptmux;\033\033]52;c;%s\a\033\\' "$encoded" > "$client_tty" ;;
  esac

  printf -- '\033]52;c;%s\a' "$encoded" > "$client_tty"
fi

# Mirror to pbcopy only when running locally
if [ -z "${SSH_CONNECTION:-}" ]; then
  printf -- '%s' "$selection" | pbcopy
fi
