#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required to install dev tools." >&2
  exit 1
fi

cd "$REPO_ROOT"

# Install CLI tools via Homebrew
brew bundle --file brew/Brewfile.dev
stow -t "$HOME" ghostty lazygit

# Install Volta (Node version manager)
export VOLTA_HOME="$HOME/.volta"
if [[ ! -d "$VOLTA_HOME" ]]; then
  curl https://get.volta.sh | bash -s -- --skip-setup
fi
export PATH="$VOLTA_HOME/bin:$PATH"
volta install node

# Install pyenv (Python version manager)
export PYENV_ROOT="$HOME/.pyenv"
if [[ ! -d "$PYENV_ROOT" ]]; then
  curl -fsSL https://pyenv.run | bash
fi
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
PYTHON_LATEST=$(pyenv install --list | grep -E '^\s*3\.[0-9]+\.[0-9]+$' | tail -1 | tr -d ' ')
pyenv install -s "$PYTHON_LATEST"
pyenv global "$PYTHON_LATEST"

# Install Rust via rustup
if [[ ! -d "$HOME/.cargo" ]]; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
fi
export PATH="$HOME/.cargo/bin:$PATH"

# Install SDKMAN (JDK version manager)
export SDKMAN_DIR="$HOME/.sdkman"
if [[ ! -d "$SDKMAN_DIR" ]]; then
  curl -s "https://get.sdkman.io?rcupdate=false" | bash
fi

# Restore Claude Code settings
bash scripts/restore-claude-settings.sh

if ! command -v claude >/dev/null 2>&1; then
  echo "Claude Code CLI was not found after installation." >&2
  exit 1
fi

claude plugin marketplace add https://github.com/anthropics/claude-plugins-official.git

bash scripts/restore-codex-config.sh
