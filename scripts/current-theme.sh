#!/usr/bin/env bash

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
