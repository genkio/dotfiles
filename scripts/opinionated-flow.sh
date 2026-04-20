#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/genkio/dotfiles.git}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
INCLUDE_APPS=0
INCLUDE_DEV=0
BOOTSTRAP_MACOS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --include-all)
      INCLUDE_APPS=1
      INCLUDE_DEV=1
      ;;
    --include-apps)
      INCLUDE_APPS=1
      ;;
    --include-dev)
      INCLUDE_DEV=1
      ;;
    --bootstrap-macos)
      BOOTSTRAP_MACOS=1
      ;;
    -h|--help)
      echo "Usage: $(basename "$0") [--include-all] [--include-apps] [--include-dev] [--bootstrap-macos]"
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
  if git -C "$DOTFILES_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Using existing repo at $DOTFILES_DIR"
  else
    echo "Error: $DOTFILES_DIR looks like a git repo, but it is incomplete or corrupt." >&2
    echo "Remove it and rerun the bootstrap." >&2
    exit 1
  fi
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
  echo "Homebrew not found. Installing..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Add brew to PATH for this session (Apple Silicon vs Intel)
  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -f /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
fi

if ! command -v stow >/dev/null 2>&1; then
  echo "GNU stow not found. Installing with Homebrew..."
  brew install stow
fi

brew bundle --file brew/Brewfile.base
sudo brew services start tailscale
stow -t "$HOME" brew nvim nvim-next tmux yazi zsh

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
if [[ -e "$HOME/.ssh/config" && ! -L "$HOME/.ssh/config" ]]; then
  echo "Skipping ssh stow: ~/.ssh/config already exists and is not a symlink."
  echo "Move it aside and run 'cd $DOTFILES_DIR && stow ssh' when you're ready."
else
  stow -t "$HOME" ssh
fi

TPM_DIR="$HOME/.tmux/plugins/tpm"
if [[ -d "$TPM_DIR/.git" ]]; then
  echo "TPM already installed at $TPM_DIR"
elif [[ -e "$TPM_DIR" ]]; then
  echo "Skipping TPM install: $TPM_DIR exists and is not a git repo."
else
  mkdir -p "$(dirname "$TPM_DIR")"
  git clone https://github.com/tmux-plugins/tpm "$TPM_DIR"
fi
if [[ -x "$TPM_DIR/bin/install_plugins" ]]; then
  "$TPM_DIR/bin/install_plugins"
  echo "Installed tmux plugins from ~/.tmux.conf"
fi

if [[ ! -f "$HOME/.gitignore_global" ]]; then
  echo "Downloading standard global gitignore to ~/.gitignore_global"
  curl -fsSL "https://raw.githubusercontent.com/github/gitignore/master/Global/macOS.gitignore" -o "$HOME/.gitignore_global"
fi

if [[ -e "$HOME/.gitconfig" && ! -L "$HOME/.gitconfig" ]]; then
  echo "Skipping git stow: ~/.gitconfig already exists and is not a symlink."
  echo "Move it aside and run 'cd $DOTFILES_DIR && stow git' when you're ready."
else
  stow -t "$HOME" git
  if [[ ! -e "$HOME/.gitconfig.local" ]]; then
    cp "$DOTFILES_DIR/git/.gitconfig.local.example" "$HOME/.gitconfig.local"
    echo "Seeded ~/.gitconfig.local from $DOTFILES_DIR/git/.gitconfig.local.example"
    echo "Edit ~/.gitconfig.local for your private Git identity."
  fi
fi

if [[ "$INCLUDE_APPS" -eq 1 ]]; then
  brew bundle --file brew/Brewfile.apps
  stow -t "$HOME" hammerspoon

  mkdir -p "$HOME/.config/karabiner"
  if [[ -e "$HOME/.config/karabiner/karabiner.json" && ! -L "$HOME/.config/karabiner/karabiner.json" ]]; then
    echo "Skipping karabiner stow: ~/.config/karabiner/karabiner.json already exists and is not a symlink."
    echo "Move it aside and run 'cd $DOTFILES_DIR && stow karabiner' when you're ready."
  else
    stow -t "$HOME" karabiner
  fi
fi

if [[ "$INCLUDE_DEV" -eq 1 ]]; then
  bash scripts/setup-dev.sh
fi

if [[ "$BOOTSTRAP_MACOS" -eq 1 ]]; then
  if [[ ! -f scripts/macos-bootstrap.sh ]]; then
    echo "Error: scripts/macos-bootstrap.sh not found." >&2
    exit 1
  fi

  bash scripts/macos-bootstrap.sh
fi
