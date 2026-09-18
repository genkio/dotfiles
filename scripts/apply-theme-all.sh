#!/usr/bin/env bash

set -euo pipefail

dotfiles="${DOTFILES_DIR:-$HOME/dotfiles}"

"$dotfiles/tmux/bin/apply-theme.sh" || true
"$dotfiles/scripts/apply-alacritty-theme.sh" || true
"$dotfiles/scripts/apply-terminal-colors.sh" || true
