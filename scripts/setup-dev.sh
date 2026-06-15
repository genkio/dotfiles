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
stow -t "$HOME" kitty mise
# Seed kitty's active theme file so its first launch has colors. Resolved
# repo root so it works cloned outside ~/dotfiles; non-fatal so a cosmetic seed
# failure can't abort provisioning (theme-toggle.sh re-seeds on the next flip).
DOTFILES_DIR="$REPO_ROOT" bash scripts/apply-kitty-theme.sh \
  || echo "Warning: kitty theme seed failed; theme-toggle.sh re-seeds on the next flip." >&2
DOTFILES_DIR="$REPO_ROOT" bash scripts/apply-kitty-icon.sh \
  || echo "Warning: kitty icon install failed (cosmetic)." >&2

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

if ! command -v maestral >/dev/null 2>&1; then
  mise exec -- uv tool install maestral
  # Enable autostart on login with `dropbox autostart on`
fi

# Restore Claude Code settings
bash scripts/restore-claude-settings.sh

# Idempotent: `add` errors (and aborts under set -e) if the marketplace exists.
if ! claude plugin marketplace list 2>/dev/null | grep -q 'claude-plugins-official'; then
  claude plugin marketplace add https://github.com/anthropics/claude-plugins-official.git
fi

bash scripts/restore-codex-config.sh
