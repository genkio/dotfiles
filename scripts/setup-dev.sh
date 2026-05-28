#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required to install dev tools." >&2
  exit 1
fi

cd "$REPO_ROOT"

# Skip the slow `brew bundle` install attempt when every entry is already
# installed AND up-to-date. `brew bundle check` only dependency-resolves
# (no install). HOMEBREW_NO_AUTO_UPDATE=1 keeps the probe itself fast;
# the real install below can still auto-update when it actually runs.
brew_bundle_install() {
  local file="$1"
  if HOMEBREW_NO_AUTO_UPDATE=1 brew bundle check --file "$file" >/dev/null 2>&1; then
    echo "brew bundle: $file already satisfied, skipping"
    return 0
  fi
  brew bundle --file "$file"
}

# Install dev tools via Homebrew
brew_bundle_install brew/Brewfile.dev
stow -t "$HOME" ghostty mise

# mise: node, python, java, go, uv + global npm tools (versions declared in mise/.config/mise/config.toml)
# Install node first so `npm` exists when activate resolves `npm:*@latest` versions.
mise install node
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
