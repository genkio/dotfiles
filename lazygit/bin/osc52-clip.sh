#!/usr/bin/env bash
set -euo pipefail

text=${1:-}

# If no text arg, fall back to stdin (should not happen in lazygit, but keeps it reusable)
if [ -z "$text" ]; then
  text=$(cat)
fi

# Feed the text to the shared OSC52 helper (it will auto-detect the tmux client TTY)
printf -- '%s' "$text" | /Users/neo/dotfiles/tmux/bin/osc52-copy.sh
