#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required to install coding agent CLIs." >&2
  exit 1
fi

cd "$REPO_ROOT"

brew bundle --file brew/Brewfile.coding-agents
bash scripts/restore-claude-settings.sh
bash scripts/restore-codex-config.sh
