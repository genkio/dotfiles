#!/usr/bin/env bash
#
# Print the currently effective theme (light or dark).
#
# Resolution order:
#   1. Override file at $XDG_CACHE_HOME/dotfiles/theme-override.
#   2. macOS appearance via `defaults read -g AppleInterfaceStyle`.
#
# Consumers: tmux/bin/apply-theme.sh, nvim's colors.lua, theme-toggle.sh.

set -euo pipefail

override="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/theme-override"

if [ -f "$override" ]; then
  read -r value < "$override" || true
  case "$value" in
    light|dark) printf '%s\n' "$value"; exit 0 ;;
  esac
fi

if defaults read -g AppleInterfaceStyle 2>/dev/null | grep -q Dark; then
  printf 'dark\n'
else
  printf 'light\n'
fi
