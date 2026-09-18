#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

BIN="$HOME/.local/bin/mise"

installed_version() {
  [[ -x "$BIN" ]] || return 1
  "$BIN" --version 2>/dev/null | awk '{print $1}'
}

if [[ "${1:-}" == "--dry-run" || "${1:-}" == "-n" ]]; then
  have="$(installed_version || true)"
  if [[ -n "$have" ]]; then
    echo "  mise: $have at $BIN, would install only if upstream is newer"
  else
    echo "  mise: would install the current release to $BIN"
  fi
  exit 0
fi

curl -fsSL https://mise.run | MISE_INSTALL_HELP=0 sh
