#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/lib.sh"

if ! command -v brew >/dev/null 2>&1; then
  err "Homebrew is required to install dev tools."
  exit 1
fi

cd "$REPO_ROOT"

brew_bundle_install() {
  local file="$1"
  if HOMEBREW_NO_AUTO_UPDATE=1 brew bundle check --file "$file" >/dev/null 2>&1; then
    echo "brew bundle: $file already satisfied, skipping"
    return 0
  fi
  brew bundle --file "$file" || warn "some entries in $file failed to install; continuing setup."
}

trust_brewfile_taps brew/Brewfile.dev
brew_bundle_install brew/Brewfile.dev
bash scripts/install-alacritty.sh \
  || warn "Alacritty install failed; rerun scripts/install-alacritty.sh."
stow -t "$HOME" alacritty mise
DOTFILES_DIR="$REPO_ROOT" bash scripts/apply-alacritty-theme.sh \
  || warn "Alacritty theme seed failed; theme-toggle.sh re-seeds on the next flip."

export PATH="$HOME/.local/bin:$PATH"

if ! command -v mise >/dev/null 2>&1; then
  bash scripts/install-mise.sh
fi

echo "mise: installing toolchains and global npm tools (quiet, takes a few minutes)..."
mise install --quiet node
eval "$(mise activate bash --shims)"
mise install --quiet || warn "some toolchains/global npm tools failed to install; continuing setup."

if ! command -v claude >/dev/null 2>&1; then
  curl -fsSL https://claude.ai/install.sh | bash
fi

if ! command -v maestral >/dev/null 2>&1; then
  mise exec -- uv python install --quiet 3.13
  mise exec -- uv tool install --quiet maestral \
    --managed-python --python 3.13 --with 'rubicon-objc<0.5.5'
fi

bash scripts/restore-claude-settings.sh

if ! claude plugin marketplace list 2>/dev/null | grep -q 'claude-plugins-official'; then
  claude plugin marketplace add https://github.com/anthropics/claude-plugins-official.git
fi

bash scripts/restore-pi-settings.sh

bash scripts/install-agent-skills.sh
