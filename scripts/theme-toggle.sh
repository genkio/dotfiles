#!/usr/bin/env bash

set -euo pipefail

dotfiles="${DOTFILES_DIR:-$HOME/dotfiles}"
override_dir="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles"
override="$override_dir/theme-override"

current="$("$dotfiles/scripts/current-theme.sh")"
if [ "$current" = "dark" ]; then
  next=light
else
  next=dark
fi

mkdir -p "$override_dir"
printf '%s\n' "$next" > "$override"

"$dotfiles/scripts/apply-theme-all.sh"
