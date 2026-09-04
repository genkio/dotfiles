#!/usr/bin/env bash
#
# Flip the effective theme (light <-> dark). Writes the override file
# (current-theme.sh reads it), then re-applies across nvim (fs_event watcher),
# tmux, Alacritty's config, and the live terminal via OSC. Bound to tmux
# prefix+t: one manual flip, local or SSH, so macOS-appearance watching is moot.
# Revert to macOS appearance: rm the override + alacritty-theme-active.toml under
# $XDG_CACHE_HOME/dotfiles.

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

# tmux + Alacritty's config + the live terminal (OSC). A manual flip holds until
# the next client attach/detach, when client-theme.sh recomputes from scratch.
"$dotfiles/scripts/apply-theme-all.sh"
