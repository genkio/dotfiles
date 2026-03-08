#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
SOURCE_FILE="$REPO_ROOT/codex/.codex/config.toml.example"
TARGET_DIR="$HOME/.codex"
TARGET_FILE="$TARGET_DIR/config.toml"

if [[ ! -f "$SOURCE_FILE" ]]; then
  echo "Codex config example not found at $SOURCE_FILE" >&2
  exit 1
fi

mkdir -p "$TARGET_DIR"

if [[ -e "$TARGET_FILE" ]]; then
  echo "Skipping Codex config restore: $TARGET_FILE already exists."
  exit 0
fi

cp "$SOURCE_FILE" "$TARGET_FILE"
echo "Seeded $TARGET_FILE from $SOURCE_FILE"
