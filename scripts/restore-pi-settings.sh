#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/lib.sh"

if ! command -v stow >/dev/null 2>&1; then
  err "GNU stow is required to restore Pi settings."
  exit 1
fi

# extensions/ must exist before stow runs so it links the extension files into a
# real directory rather than folding the whole tree; Pi and herdr both drop
# files there (herdr installs its own agent-state extension).
mkdir -p "$HOME/.pi/agent" "$HOME/.pi/agent/extensions" "$HOME/.pi/agent/skills"

cd "$REPO_ROOT"
stow -t "$HOME" pi
echo "Restored Pi settings, keybindings, and extensions into ~/.pi/agent"

stow -t "$HOME/.pi/agent/skills" skills
echo "Restored shared coding-agent skills into ~/.pi/agent/skills"

# pi-web-access is the default web search + fetch extension. It is installed
# through pi itself, not stowed, because ~/.pi/agent/npm is pi's package tree
# and pi owns the package list in ~/.pi/agent/settings.json. Non-fatal: a
# network hiccup here should not abort provisioning.
if ! command -v pi >/dev/null 2>&1; then
  warn "pi not found; skipping the pi-web-access install. Later: pi install npm:pi-web-access"
elif [[ -d "$HOME/.pi/agent/npm/node_modules/pi-web-access" ]]; then
  echo "Pi package pi-web-access already installed"
elif pi install npm:pi-web-access; then
  echo "Installed Pi package pi-web-access"
else
  warn "pi install npm:pi-web-access failed; rerun it later."
fi

# web-search.json can hold API keys and is rewritten by pi-web-access when the
# curator changes providers, so it is seeded from the tracked example, never
# stowed. settings.json is part of the stowed pi package instead: it holds no
# secrets (provider auth lives in auth.json), so its changes are worth seeing in
# git. An existing file keeps its own values; missing keys are filled in.
merge_json_defaults() {  # merge_json_defaults <target> <example> <label>
  local target="$1" example="$2" label="$3" tmp
  if [[ ! -e "$target" ]]; then
    cp "$example" "$target"
    echo "Seeded $label from the example"
    return
  fi
  tmp="$(mktemp)"
  # example * target: target wins on conflicts, example fills missing keys.
  if jq -s '.[0] * .[1]' "$example" "$target" > "$tmp" 2>/dev/null; then
    # Compare parsed, key-sorted JSON: a value pi already set (even a different
    # one) counts as set, so a reordered rewrite is not a change.
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
