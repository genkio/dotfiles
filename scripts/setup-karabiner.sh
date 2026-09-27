#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib.sh"

APP="/Applications/Karabiner-Elements.app"
PKG_DIR="$REPO_ROOT/karabiner/.config/karabiner"
TARGET="$HOME/.config/karabiner"
CONSOLE_AGENT="org.pqrs.service.agent.Karabiner-Console-User-Server"

if ! command -v stow >/dev/null 2>&1; then
  err "GNU stow is required; run 'make core' first."
  exit 1
fi

# Karabiner ignores edits to a symlinked karabiner.json, so the whole directory must be the symlink.
if [[ -L "$TARGET" && "$(cd -P -- "$TARGET" && pwd)" == "$(cd -P -- "$PKG_DIR" && pwd)" ]]; then
  echo "~/.config/karabiner already links to the dotfiles."
else
  if [[ -e "$TARGET" || -L "$TARGET" ]]; then
    backup="$TARGET.bak-$(date +%Y%m%d%H%M%S)"
    mv "$TARGET" "$backup"
    echo "Backed up the existing ~/.config/karabiner to $backup"
  fi

  mkdir -p "$HOME/.config"
  stow -R -t "$HOME" -d "$REPO_ROOT" karabiner

  if [[ ! -L "$TARGET" ]]; then
    err "stow did not link ~/.config/karabiner as a directory; Karabiner won't see config changes."
    exit 1
  fi
  echo "Linked ~/.config/karabiner to the dotfiles."
fi

if [[ ! -d "$APP" ]]; then
  echo "Karabiner-Elements is not installed. Install it with:"
  echo "  brew install --cask karabiner-elements"
  echo "then open it and allow its driver extension and Input Monitoring."
  exit 0
fi

# The running agent keeps watching the old directory until restarted.
if launchctl print "gui/$(id -u)/$CONSOLE_AGENT" >/dev/null 2>&1; then
  launchctl kickstart -k "gui/$(id -u)/$CONSOLE_AGENT" ||
    warn "could not restart Karabiner; quit and reopen Karabiner-Elements to load the config."
  echo "Restarted Karabiner to load the config."
else
  echo "Open Karabiner-Elements once and allow its driver extension and Input Monitoring."
fi
