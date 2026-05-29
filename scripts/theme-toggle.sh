#!/usr/bin/env bash
#
# Flip the effective theme (light <-> dark) without touching macOS appearance.
# Writes an override file that current-theme.sh reads, then re-applies the
# theme across tmux and Ghostty. Nvim picks up the change on its next
# FocusGained (see lua/config/colors.lua).
#
# To revert to following macOS appearance, delete both:
#   $XDG_CACHE_HOME/dotfiles/theme-override
#   $XDG_CACHE_HOME/dotfiles/ghostty-theme-active.conf

set -euo pipefail

dotfiles="${DOTFILES_DIR:-$HOME/dotfiles}"
override_dir="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles"
override="$override_dir/theme-override"
ghostty_active="$override_dir/ghostty-theme-active.conf"

current="$("$dotfiles/scripts/current-theme.sh")"
if [ "$current" = "dark" ]; then
  next=light
else
  next=dark
fi

mkdir -p "$override_dir"
printf '%s\n' "$next" > "$override"

# Tmux: idempotent; no-ops if no tmux server is running.
"$dotfiles/tmux/bin/apply-theme.sh"

# Ghostty: write the include fragment that overrides the main `theme = light:..,dark:..`
# auto-switch line, then SIGUSR2 to make Ghostty reload its config.
mkdir -p "$(dirname "$ghostty_active")"
if [ "$next" = "dark" ]; then
  printf 'theme = Nordfox\n' > "$ghostty_active"
else
  printf 'theme = Dawnfox-soft\n' > "$ghostty_active"
fi
pkill -USR2 -x ghostty 2>/dev/null || true
