#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/lib.sh"

if ! command -v brew >/dev/null 2>&1; then
  err "tailscale needs Homebrew; run 'make core' first."
  exit 1
fi

if ! command -v tailscale >/dev/null 2>&1; then
  echo "Installing tailscale (a Go build on Intel, so this is not quick)..."
  brew install tailscale
fi

OPERATOR="${SUDO_USER:-$USER}"

backend_state() {
  tailscale status --json 2>/dev/null | sed -n 's/.*"BackendState": *"\([^"]*\)".*/\1/p' | head -1
}

if [[ -z "$(backend_state)" ]]; then
  echo "tailscaled is not responding; starting the service..."
  sudo brew services start tailscale ||
    warn "could not start the tailscale service; try 'sudo brew services start tailscale'."
fi

if [[ "$(backend_state)" == "Running" ]]; then
  echo "Already logged in."
  bash "$SCRIPT_DIR/install-taildrop.sh" || warn "taildrop receiver not loaded."
  tailscale status
  exit 0
fi

echo "A login URL follows; authorize this machine in the browser."
sudo tailscale up --ssh --operator="$OPERATOR"
bash "$SCRIPT_DIR/install-taildrop.sh" || warn "taildrop receiver not loaded."
tailscale status
