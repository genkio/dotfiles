#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required to install dev tools." >&2
  exit 1
fi

cd "$REPO_ROOT"

# Install dev tools via Homebrew
brew bundle --file brew/Brewfile.dev
stow -t "$HOME" ghostty

if [[ "$(uname -s)" == "Darwin" ]]; then
  defaults write wang.jianing.app.OpenInEditor-Lite LiteDefaultEditor Ghostty
fi

# Install Volta (Node version manager)
export VOLTA_HOME="$HOME/.volta"
export PATH="$VOLTA_HOME/bin:$PATH"
if ! command -v volta >/dev/null 2>&1; then
  curl https://get.volta.sh | bash -s -- --skip-setup
fi
volta install node

# Install pyenv (Python version manager)
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
if ! command -v pyenv >/dev/null 2>&1; then
  curl -fsSL https://pyenv.run | bash
fi
eval "$(pyenv init -)"
PYTHON_LATEST=$(pyenv install --list | grep -E '^\s*3\.[0-9]+\.[0-9]+$' | tail -1 | tr -d ' ')
pyenv install -s "$PYTHON_LATEST"
pyenv global "$PYTHON_LATEST"

# Install Rust via rustup
export PATH="$HOME/.cargo/bin:$PATH"
if ! command -v rustup >/dev/null 2>&1; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
fi

# Restore Claude Code settings
bash scripts/restore-claude-settings.sh

if ! command -v claude >/dev/null 2>&1; then
  echo "Claude Code CLI was not found after installation." >&2
  exit 1
fi

claude plugin marketplace add https://github.com/anthropics/claude-plugins-official.git

bash scripts/restore-codex-config.sh
