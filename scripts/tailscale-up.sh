#!/usr/bin/env bash
set -euo pipefail

# Put this machine on the tailnet: install the formula, start its daemon, and
# log in (the one step that needs a browser).
#
# Owns the whole of tailscale rather than sharing it with a setup phase. It is
# the formula and not the tailscale-app cask because this machine has to ACCEPT
# Tailscale SSH, and that server component runs only on Linux and this
# open-source tailscaled. Two consequences that keep it out of `make all`: it is
# a Go build with no x86_64 bottle, so on Intel it compiles; and it leaves a root
# LaunchDaemon behind, which is not something a bootstrap should do unasked.
#
# Wraps `sudo tailscale up --ssh --operator=<user>`:
#   --ssh       enables Tailscale SSH into this machine
#   --operator  lets the tailscale CLI run without sudo afterwards
#
# Exit-node flags are deliberately not bundled in: passing them to `up` can drop
# them silently. Advertise with `sudo tailscale set --advertise-exit-node` (then
# approve in the admin console), and consume one with scripts/tailscale-exit.sh.

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

# Root via `sudo make tailscale` would make root the operator, which defeats the
# point of the flag.
OPERATOR="${SUDO_USER:-$USER}"

backend_state() {
  tailscale status --json 2>/dev/null | sed -n 's/.*"BackendState": *"\([^"]*\)".*/\1/p' | head -1
}

# The brew build runs tailscaled as a root LaunchDaemon, so the CLI has nothing
# to talk to until the service is started; `up` would fail with a connect error.
if [[ -z "$(backend_state)" ]]; then
  echo "tailscaled is not responding; starting the service..."
  sudo brew services start tailscale ||
    warn "could not start the tailscale service; try 'sudo brew services start tailscale'."
fi

if [[ "$(backend_state)" == "Running" ]]; then
  echo "Already logged in."
  tailscale status
  exit 0
fi

echo "A login URL follows; authorize this machine in the browser."
sudo tailscale up --ssh --operator="$OPERATOR"
tailscale status
