#!/usr/bin/env bash
set -euo pipefail

# Log this machine into the tailnet (the one post-`make` step that needs a
# browser).
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

if ! command -v tailscale >/dev/null 2>&1; then
  err "tailscale not installed; it ships in brew/Brewfile.base, so run 'make' or 'brew install tailscale'."
  exit 1
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
