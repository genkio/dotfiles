#!/usr/bin/env bash
#
# Flip the effective theme (light <-> dark) without touching macOS appearance.
# Writes an override file that current-theme.sh reads, then re-applies the
# theme across tmux and Alacritty. Nvim picks up the change instantly via its
# fs_event watcher on the override file (see lua/config/colors.lua).
#
# To revert to following macOS appearance, delete both:
#   $XDG_CACHE_HOME/dotfiles/theme-override
#   $XDG_CACHE_HOME/dotfiles/alacritty-theme-active.toml
# (Alacritty drops back to its baseline flexoki-light import until the next
# appearance change regenerates the active file via theme_watcher.lua.)

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

# Tmux: idempotent; no-ops if no tmux server is running.
"$dotfiles/tmux/bin/apply-theme.sh"

# Alacritty: rewrite its active colors file; live_config_reload picks it up.
# Non-fatal like the tmux step so a cosmetic seed failure can't abort the toggle.
"$dotfiles/scripts/apply-alacritty-theme.sh" || true
