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

# herdlet's skill ships in its keg and the link to it is absolute (the Homebrew
# prefix differs per arch), so it is machine-local rather than stowed.
bash "$SCRIPT_DIR/link-herdlet.sh"
