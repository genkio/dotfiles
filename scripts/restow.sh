#!/usr/bin/env bash
set -euo pipefail

# Restow every package this repo manages.
#
# `stow -R` removes stale symlinks and recreates current ones in one pass,
# so this picks up added, removed, and renamed files after edits to the
# dotfiles repo. Use this for routine re-stow.
#
# Does NOT run brew bundle, macOS defaults, or any installers. For a full
# machine bootstrap use `make` / `make bootstrap` / `make dev`.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

if ! command -v stow >/dev/null 2>&1; then
  echo "GNU stow is required to restow packages." >&2
  exit 1
fi

cd "$REPO_ROOT"

# Pre-create dirs that need to exist before stow runs so stow doesn't fold
# them as symlinks (mpv writes runtime state into its config dir; skills
# stow into nested per-agent dirs).
mkdir -p "$HOME/.config/mpv"
mkdir -p "$HOME/.claude" "$HOME/.claude/skills"
mkdir -p "$HOME/.codex" "$HOME/.codex/skills"

# Packages that stow straight to $HOME with no guards.
HOME_PKGS=(brew mpv nvim tmux yazi zsh hammerspoon mise claude codex vim)

echo "Restowing into ~: ${HOME_PKGS[*]}"
stow -R -t "$HOME" "${HOME_PKGS[@]}"

# ssh and git: skip when a real file already exists at the target so we
# don't clobber a hand-edited config (matches opinionated-flow.sh).
if [[ -e "$HOME/.ssh/config" && ! -L "$HOME/.ssh/config" ]]; then
  echo "Skipping ssh: ~/.ssh/config exists and is not a symlink."
else
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  stow -R -t "$HOME" ssh
fi

if [[ -e "$HOME/.gitconfig" && ! -L "$HOME/.gitconfig" ]]; then
  echo "Skipping git: ~/.gitconfig exists and is not a symlink."
else
  stow -R -t "$HOME" git
fi

# Skills are stowed into nested per-agent dirs, each needs its own -t.
echo "Restowing skills into ~/.claude/skills and ~/.codex/skills"
stow -R -t "$HOME/.claude/skills" skills
stow -R -t "$HOME/.codex/skills" skills

echo "Done."
