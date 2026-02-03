#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/genkio/dotfiles.git}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
INCLUDE_APPS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --include-apps)
      INCLUDE_APPS=1
      ;;
    -h|--help)
      echo "Usage: $(basename "$0") [--include-apps]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
  shift
done

if [[ -d "$DOTFILES_DIR/.git" ]]; then
  echo "Using existing repo at $DOTFILES_DIR"
else
  if [[ -e "$DOTFILES_DIR" ]]; then
    echo "Error: $DOTFILES_DIR exists but is not a git repo." >&2
    exit 1
  fi
  echo "Cloning $REPO_URL to $DOTFILES_DIR"
  git clone "$REPO_URL" "$DOTFILES_DIR"
fi

cd "$DOTFILES_DIR"

if ! command -v brew >/dev/null 2>&1; then
  echo "Error: Homebrew not found. Install brew first." >&2
  exit 1
fi

if ! command -v stow >/dev/null 2>&1; then
  echo "GNU stow not found. Installing with Homebrew..."
  brew install stow
fi

brew bundle --file brew/Brewfile.base
stow brew lazygit nvim tmux vim zsh

if [[ "$INCLUDE_APPS" -eq 1 ]]; then
  brew bundle --file brew/Brewfile.apps
  stow claude ghostty
fi
