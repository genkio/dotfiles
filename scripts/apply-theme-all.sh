#!/usr/bin/env bash
#
# Re-apply the currently effective theme (current-theme.sh) everywhere: tmux,
# Alacritty's active colors file, and the live terminal via OSC. nvim picks it
# up on its own through the fs_event watcher on the override file.
#
# Callers: theme-toggle.sh (manual prefix+t) and tmux/bin/client-theme.sh
# (automatic flip on client attach/detach). Cosmetic steps are non-fatal so a
# missing Alacritty config or an unwritable tty can't abort the flip.

set -euo pipefail

dotfiles="${DOTFILES_DIR:-$HOME/dotfiles}"

"$dotfiles/tmux/bin/apply-theme.sh" || true
"$dotfiles/scripts/apply-alacritty-theme.sh" || true
"$dotfiles/scripts/apply-terminal-colors.sh" || true
