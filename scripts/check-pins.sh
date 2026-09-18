#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/lib.sh"

export PATH="$HOME/.local/bin:$PATH"

pinned_playwright="$(sed -n 's/^"npm:@playwright\/cli" = "\(.*\)"$/\1/p' \
  "$REPO_ROOT/mise/.config/mise/conf.d/dev.toml")"
pinned_alacritty="$(sed -n 's/^VERSION=\(.*\)$/\1/p' "$SCRIPT_DIR/install-alacritty.sh")"

section "pins"

action() {
  echo "    -> $*"
  [[ -n "${CHECK_PINS_ACTIONS:-}" ]] && echo "$*" >>"$CHECK_PINS_ACTIONS"
  return 0
}

check_playwright() {
  local pin="$1" json trusted mise_latest

  if [[ -z "$pin" || "$pin" == "latest" ]]; then
    echo "  @playwright/cli: not pinned (tracking latest), nothing to audit"
    return
  fi

  mise_latest="$(mise latest npm:@playwright/cli 2>/dev/null)" || true
  if [[ -z "$mise_latest" ]]; then
    warn "  @playwright/cli $pin: could not ask mise what it resolves to"
    return
  fi

  if [[ "$mise_latest" == "$pin" ]]; then
    echo "  @playwright/cli $pin: mise resolves latest to the pinned version, pin is a no-op"
    action "drop the pin: \"npm:@playwright/cli\" = \"latest\" in mise/.config/mise/conf.d/dev.toml"
    return
  fi

  json="$(curl -fsS --max-time 15 "https://registry.npmjs.org/@playwright/cli/$mise_latest" 2>/dev/null)" || {
    warn "  @playwright/cli $pin: could not reach the npm registry"
    return
  }

  trusted="$(jq -r '._npmUser.trustedPublisher != null' <<<"$json")"

  if [[ "$trusted" == "true" ]]; then
    echo "  @playwright/cli $pin: mise now resolves latest to $mise_latest, which HAS a trusted publisher"
    action "drop the pin: \"npm:@playwright/cli\" = \"latest\" in mise/.config/mise/conf.d/dev.toml"
  else
    echo "  @playwright/cli $pin: mise resolves latest to $mise_latest, still no trusted publisher, keep the pin"
  fi
}

check_alacritty() {
  local pin="$1" json version disabled reason

  json="$(curl -fsS --max-time 15 https://formulae.brew.sh/api/cask/alacritty.json 2>/dev/null)" || {
    warn "  alacritty $pin: could not reach the Homebrew API"
    return
  }

  version="$(jq -r '.version' <<<"$json")"
  disabled="$(jq -r '.disabled' <<<"$json")"
  reason="$(jq -r '.disable_reason // "n/a"' <<<"$json")"

  if [[ "$disabled" == "true" ]]; then
    echo "  alacritty $pin: cask still disabled ($reason), keep the dmg install"
    if [[ "$version" != "$pin" ]]; then
      echo "    note: the cask now tracks $version; bump VERSION and SHA256 in install-alacritty.sh"
    fi
  else
    echo "  alacritty $pin: cask is ENABLED again at $version"
    action "restore 'cask \"alacritty\"' in brew/Brewfile.dev and drop scripts/install-alacritty.sh"
  fi
}

check_playwright "$pinned_playwright"
check_alacritty "$pinned_alacritty"

exit 0
