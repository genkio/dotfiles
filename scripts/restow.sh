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

source "$SCRIPT_DIR/lib.sh"

if ! command -v stow >/dev/null 2>&1; then
  err "GNU stow is required to restow packages."
  exit 1
fi

# --dry-run: stow's own simulation, so the preview comes from stow's conflict
# detection rather than a guess about what it would do. -v to make it say so.
STOW_FLAGS=(-R)
if [[ "${1:-}" == "--dry-run" || "${1:-}" == "-n" ]]; then
  STOW_FLAGS+=(-n -v)
  echo "(dry run: no symlinks will be changed)"
fi

cd "$REPO_ROOT"

# Pre-create dirs that need to exist before stow runs so stow doesn't fold
# them as symlinks (mpv writes runtime state into its config dir; skills
# stow into nested per-agent dirs).
mkdir -p "$HOME/.config/mpv"
mkdir -p "$HOME/.claude" "$HOME/.claude/skills"
mkdir -p "$HOME/.codex" "$HOME/.codex/skills"

# Packages that stow straight to $HOME with no guards.
HOME_PKGS=(alacritty brew mpv nvim tmux yazi zsh hammerspoon mise claude codex vim)

echo "Restowing into ~: ${HOME_PKGS[*]}"
stow "${STOW_FLAGS[@]}" -t "$HOME" "${HOME_PKGS[@]}"

# ssh and git: skip when a real file already exists at the target so we
# don't clobber a hand-edited config (matches opinionated-flow.sh).
if [[ -e "$HOME/.ssh/config" && ! -L "$HOME/.ssh/config" ]]; then
  echo "Skipping ssh: ~/.ssh/config exists and is not a symlink."
else
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  stow "${STOW_FLAGS[@]}" -t "$HOME" ssh
fi

if [[ -e "$HOME/.gitconfig" && ! -L "$HOME/.gitconfig" ]]; then
  echo "Skipping git: ~/.gitconfig exists and is not a symlink."
else
  stow "${STOW_FLAGS[@]}" -t "$HOME" git
fi

# Skills are stowed into nested per-agent dirs, each needs its own -t.
echo "Restowing skills into ~/.claude/skills and ~/.codex/skills"
stow "${STOW_FLAGS[@]}" -t "$HOME/.claude/skills" skills
stow "${STOW_FLAGS[@]}" -t "$HOME/.codex/skills" skills

echo "Done."
