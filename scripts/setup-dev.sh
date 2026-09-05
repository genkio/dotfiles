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
  # brew bundle keeps going past a failed formula/cask, installs everything
  # else, then exits non-zero. Swallow that so `set -e` doesn't abort the dev
  # flow over one bad package; warn and continue.
  brew bundle --file "$file" || warn "some entries in $file failed to install; continuing setup."
}

# Install dev tools via Homebrew
brew_bundle_install brew/Brewfile.dev
# Not a cask: see the header of install-alacritty.sh. Non-fatal so a download
# failure can't abort provisioning over one app.
bash scripts/install-alacritty.sh \
  || warn "Alacritty install failed; rerun scripts/install-alacritty.sh."
stow -t "$HOME" alacritty mise
# Seed Alacritty's active theme file so its first launch has colors. Resolved
# repo root so it works cloned outside ~/dotfiles; non-fatal so a cosmetic seed
# failure can't abort provisioning (theme-toggle.sh re-seeds on the next flip).
DOTFILES_DIR="$REPO_ROOT" bash scripts/apply-alacritty-theme.sh \
  || warn "Alacritty theme seed failed; theme-toggle.sh re-seeds on the next flip."

# mise: node, python, java, go, uv + global npm tools (versions declared in mise/.config/mise/config.toml)
# Install node first so `npm` exists when activate resolves `npm:*@latest` versions.
# --quiet: mise repaints a live multi-progress UI several times a second, and a
# captured setup log keeps every frame (~500 of 800 lines in one run). Errors and
# warnings still print; --silent would swallow those too.
echo "mise: installing toolchains and global npm tools (quiet, takes a few minutes)..."
mise install --quiet node
eval "$(mise activate bash)"
# Non-fatal like brew_bundle_install above: one unresolvable npm tool (e.g. a
# registry trust-policy rejection) shouldn't abort the rest of provisioning.
mise install --quiet || warn "some toolchains/global npm tools failed to install; continuing setup."

# Install Claude Code via official shell installer (self-updates via `claude update`)
export PATH="$HOME/.local/bin:$PATH"
if ! command -v claude >/dev/null 2>&1; then
  curl -fsSL https://claude.ai/install.sh | bash
fi

if ! command -v maestral >/dev/null 2>&1; then
  # Two upstream breaks have to be dodged at once, and fixing either alone still
  # leaves a daemon that will not start:
  #   - rubicon-objc >= 0.5.5 moved an ObjCClass("NSEvent") lookup to import
  #     time, but rubicon only ever loads Foundation/CoreFoundation, never
  #     AppKit where NSEvent lives. GUI processes get away with it; a detached
  #     daemon dies on import and `box start` only shows a Pyro5 socket error.
  #   - Python 3.14 removed asyncio.events.AbstractEventLoopPolicy, which every
  #     rubicon release to date still subclasses.
  # So the pin below 0.5.5 forces 3.13 as well. Drop both once maestral ships an
  # upper bound and rubicon moves off the removed policy API.
  #
  # --managed-python keeps the daemon off Homebrew's python@3.13. The keychain
  # ACL holding the Dropbox token is bound to the cdhash of whichever
  # interpreter wrote it, and every one of these is ad-hoc signed, so any move
  # re-prompts for the login password on each `box start`. A uv-managed
  # interpreter still moves on upgrade, but only when asked - `brew upgrade`
  # cannot drag it out from under the tool.
  mise exec -- uv python install --quiet 3.13
  mise exec -- uv tool install --quiet maestral \
    --managed-python --python 3.13 --with 'rubicon-objc<0.5.5'
  # Sign in with `maestral auth link`, then `maestral start`; autostart on login
  # is `maestral autostart -Y` (it takes -Y/-N, not on/off).
  # `maestral start` prompts for a sync folder when [sync] path is unset, so it
  # hangs with no output under a script: `maestral config set path ~/box`.
fi

# Restore Claude Code settings
bash scripts/restore-claude-settings.sh

# Idempotent: `add` errors (and aborts under set -e) if the marketplace exists.
if ! claude plugin marketplace list 2>/dev/null | grep -q 'claude-plugins-official'; then
  claude plugin marketplace add https://github.com/anthropics/claude-plugins-official.git
fi

bash scripts/restore-codex-config.sh
