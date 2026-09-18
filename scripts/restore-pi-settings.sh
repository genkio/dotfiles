#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/lib.sh"

if ! command -v stow >/dev/null 2>&1; then
  err "GNU stow is required to restore Pi settings."
  exit 1
fi

mkdir -p "$HOME/.pi/agent" "$HOME/.pi/agent/extensions" "$HOME/.pi/agent/skills"

cd "$REPO_ROOT"
stow -t "$HOME" pi
echo "Restored Pi settings, keybindings, and extensions into ~/.pi/agent"

stow -t "$HOME/.pi/agent/skills" skills
echo "Restored shared coding-agent skills into ~/.pi/agent/skills"

herdr_install_integration pi

if ! command -v pi >/dev/null 2>&1; then
  warn "pi not found; skipping the pi-web-access install. Later: pi install npm:pi-web-access"
elif [[ -d "$HOME/.pi/agent/npm/node_modules/pi-web-access" ]]; then
  echo "Pi package pi-web-access already installed"
elif pi install npm:pi-web-access; then
  echo "Installed Pi package pi-web-access"
else
  warn "pi install npm:pi-web-access failed; rerun it later."
fi

merge_json_defaults() {
  local target="$1" example="$2" label="$3" tmp
  if [[ ! -e "$target" ]]; then
    cp "$example" "$target"
    echo "Seeded $label from the example"
    return
  fi
  tmp="$(mktemp)"
  if jq -s '.[0] * .[1]' "$example" "$target" > "$tmp" 2>/dev/null; then
    if ! diff -q <(jq -S . "$target") <(jq -S . "$tmp") >/dev/null 2>&1; then
      mv "$tmp" "$target"
      echo "Filled missing defaults in $label"
    fi
  else
    warn "could not parse $target; leaving it alone."
  fi
  rm -f "$tmp"
}

merge_json_defaults "$HOME/.pi/agent/web-search.json" \
  "$REPO_ROOT/pi/.pi/agent/web-search.json.example" "~/.pi/agent/web-search.json"
