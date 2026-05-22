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
stow -t "$HOME" ghostty mise

# mise: node, python, java + global npm tools (versions declared in mise/.config/mise/config.toml)
eval "$(mise activate bash)"
mise install

# Install Claude Code via official shell installer (self-updates via `claude update`)
export PATH="$HOME/.local/bin:$PATH"
if ! command -v claude >/dev/null 2>&1; then
  curl -fsSL https://claude.ai/install.sh | bash
fi

# Restore Claude Code settings
bash scripts/restore-claude-settings.sh

claude plugin marketplace add https://github.com/anthropics/claude-plugins-official.git

bash scripts/restore-codex-config.sh
