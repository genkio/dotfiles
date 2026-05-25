#!/usr/bin/env bash
set -euo pipefail

# Opinionated first-run bootstrap for this dotfiles repo.
#
# The script is intentionally a full machine setup path, not just a stow helper:
# clone or reuse the repo, install base Homebrew packages, stow the core package
# set, seed tmux/git/ssh defaults, and optionally install GUI apps, dev tooling,
# and macOS preference tweaks. Keep this aligned with AGENTS.md/CLAUDE.md before
# changing package names or setup order.

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

# Capture password once up front. Used for sudo (kept warm via -S in the
# keepalive so it survives even if the timestamp expires during long brew
# steps) and for FileVault's fdesetup -inputplist (avoids its separate
# Secure Token prompt). Cleared on exit. Exported so macos-bootstrap.sh
# inherits it; DOTFILES_SUDO_WARMED tells children to skip their own prompt.
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  if [[ -z "${DOTFILES_SUDO_PASSWORD:-}" ]]; then
    printf 'Password (used once for sudo and FileVault): '
    stty -echo
    IFS= read -r DOTFILES_SUDO_PASSWORD
    stty echo
    printf '\n'
  fi
  export DOTFILES_SUDO_PASSWORD
  export DOTFILES_SUDO_WARMED=1

  if ! printf '%s\n' "$DOTFILES_SUDO_PASSWORD" | sudo -S -v 2>/dev/null; then
    echo "Error: sudo authentication failed." >&2
    unset DOTFILES_SUDO_PASSWORD DOTFILES_SUDO_WARMED
    exit 1
  fi

  ( while kill -0 "$$" 2>/dev/null; do
      printf '%s\n' "$DOTFILES_SUDO_PASSWORD" | sudo -S -v 2>/dev/null || true
      sleep 60
    done ) &
  SUDO_KEEPALIVE_PID=$!
  trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true; unset DOTFILES_SUDO_PASSWORD DOTFILES_SUDO_WARMED' EXIT
fi

# Wrapper that feeds the captured password to sudo via stdin. Needed because
# Homebrew's brew.sh runs `sudo --reset-timestamp` on every invocation
# (Library/Homebrew/brew.sh:~1136), so the cache is dead right after any
# `brew` call. Falls back to plain sudo when no password is set.
sudo_pw() {
  if [[ -n "${DOTFILES_SUDO_PASSWORD:-}" ]]; then
    printf '%s\n' "$DOTFILES_SUDO_PASSWORD" | sudo -S "$@"
  else
    sudo "$@"
  fi
}

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

# Run early so tap-to-click etc. apply during the long brew bundle below.
# Homebrew install above pulled in Xcode CLT -> /usr/bin/python3 (Dock mutation) works.
if [[ "$BOOTSTRAP_MACOS" -eq 1 ]]; then
  if [[ ! -f scripts/macos-bootstrap.sh ]]; then
    echo "Error: scripts/macos-bootstrap.sh not found." >&2
    exit 1
  fi

  bash scripts/macos-bootstrap.sh
fi

brew bundle --file brew/Brewfile.base
sudo_pw brew services start tailscale
# `sudo tailscale up --ssh` after `tailscale login`
mkdir -p "$HOME/.config/mpv"
stow -t "$HOME" brew mpv nvim tmux yazi zsh

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
fi

if [[ "$INCLUDE_DEV" -eq 1 ]]; then
  bash scripts/setup-dev.sh
fi
