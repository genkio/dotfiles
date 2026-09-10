#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
SOURCE_FILE="$REPO_ROOT/codex/.codex/config.toml.example"
TARGET_DIR="$HOME/.codex"
TARGET_FILE="$TARGET_DIR/config.toml"

source "$SCRIPT_DIR/lib.sh"

if [[ ! -f "$SOURCE_FILE" ]]; then
  err "Codex config example not found at $SOURCE_FILE"
  exit 1
fi

mkdir -p "$TARGET_DIR" "$TARGET_DIR/skills"

if command -v stow >/dev/null 2>&1; then
  cd "$REPO_ROOT"
  stow -t "$HOME" codex
  echo "Stowed Codex hook config into ~/.codex"
  stow -t "$TARGET_DIR/skills" skills
  echo "Restored shared coding-agent skills into ~/.codex/skills"
else
  warn "GNU stow not found; skipping stow of codex package (config.toml will still be seeded)."
fi

if [[ ! -e "$TARGET_FILE" ]]; then
  sed "s#\"~/#\"$HOME/#g" "$SOURCE_FILE" > "$TARGET_FILE"
  echo "Seeded $TARGET_FILE from $SOURCE_FILE"
  exit 0
fi

# Existing config: merge only what herdlet needs, hooks on and trusted repos.
# Top-level keys must sit before the first [table], so hooks goes to line 1.
if ! grep -q '^hooks = true' "$TARGET_FILE"; then
  printf 'hooks = true\n%s\n' "$(cat "$TARGET_FILE")" > "$TARGET_FILE"
  echo "Enabled hooks in $TARGET_FILE"
fi
while IFS= read -r project; do
  project="${project/#\~/$HOME}"
  if ! grep -qF "[projects.\"$project\"]" "$TARGET_FILE"; then
    printf '\n[projects."%s"]\ntrust_level = "trusted"\n' "$project" >> "$TARGET_FILE"
    echo "Trusted $project in $TARGET_FILE"
  fi
done < <(sed -n 's/^\[projects\."\(.*\)"\]$/\1/p' "$SOURCE_FILE")
echo "Merged herdlet settings into existing $TARGET_FILE"
