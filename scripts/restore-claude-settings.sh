#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

if ! command -v stow >/dev/null 2>&1; then
  echo "GNU stow is required to restore Claude settings." >&2
  exit 1
fi

mkdir -p "$HOME"

cd "$REPO_ROOT"
stow -t "$HOME" claude
echo "Restored Claude Code settings into ~/.claude"
