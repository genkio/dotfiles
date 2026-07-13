#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/lib.sh"

if ! command -v stow >/dev/null 2>&1; then
  err "GNU stow is required to restore Claude settings."
  exit 1
fi

mkdir -p "$HOME/.claude" "$HOME/.claude/skills"

cd "$REPO_ROOT"
stow -t "$HOME" claude
echo "Restored Claude Code settings into ~/.claude"

stow -t "$HOME/.claude/skills" skills
echo "Restored shared coding-agent skills into ~/.claude/skills"
