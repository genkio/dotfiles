#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/lib.sh"

if ! command -v stow >/dev/null 2>&1; then
  err "GNU stow is required to restore Pi settings."
  exit 1
fi

# extensions/ must exist before stow runs so it links the extension file into a
# real directory rather than folding the whole tree; Pi and herdr both drop
# files there (herdr installs its own agent-state extension).
mkdir -p "$HOME/.pi/agent" "$HOME/.pi/agent/extensions" "$HOME/.pi/agent/skills"

cd "$REPO_ROOT"
stow -t "$HOME" pi
echo "Restored Pi extension into ~/.pi/agent/extensions"

stow -t "$HOME/.pi/agent/skills" skills
echo "Restored shared coding-agent skills into ~/.pi/agent/skills"
