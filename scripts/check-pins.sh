#!/usr/bin/env bash
#
# Report whether the repo's exception pins are still needed.
#
# Two tools are pinned because upstream failed a supply-chain check, not because
# a newer version broke something:
#
#   npm:@playwright/cli  0.1.19 was published without SLSA provenance
#   alacritty            the cask is disabled, the dmg is not notarized
#
# An auto-bumper (Renovate, Dependabot) is the wrong tool here: it would undo
# the exact thing the pin is for. What goes stale instead is the *reason* - the
# pin outlives the upstream problem and nobody notices. So this checks each
# pin's escape condition and reports; it never edits anything.
#
# Advisory only: always exits 0 so a network blip can't fail a caller that
# folds this into a larger maintenance run.

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/lib.sh"

# Read the pins from the files that define them, so the audit can't drift from
# what is actually pinned.
pinned_playwright="$(sed -n 's/^"npm:@playwright\/cli" = "\(.*\)"$/\1/p' \
  "$REPO_ROOT/mise/.config/mise/config.toml")"
pinned_alacritty="$(sed -n 's/^VERSION=\(.*\)$/\1/p' "$SCRIPT_DIR/install-alacritty.sh")"

section "pins"

# Actionable lines go to the report and, when CHECK_PINS_ACTIONS names a file,
# also to that file, so a caller can reprint them in its own summary without
# capturing our stdout (which would strip the colors).
action() {
  echo "    -> $*"
  [[ -n "${CHECK_PINS_ACTIONS:-}" ]] && echo "$*" >>"$CHECK_PINS_ACTIONS"
  return 0
}

check_playwright() {
  local pin="$1" json version trusted

  if [[ -z "$pin" ]]; then
    echo "  @playwright/cli: not pinned (tracking latest), nothing to audit"
    return
  fi

  json="$(curl -fsS --max-time 15 https://registry.npmjs.org/@playwright/cli/latest 2>/dev/null)" || {
    warn "  @playwright/cli $pin: could not reach the npm registry"
    return
  }

  version="$(jq -r '.version' <<<"$json")"
  # A trusted publisher (npm's OIDC flow) is what the no-downgrade policy looks
  # for; the attestation follows from it.
  trusted="$(jq -r '._npmUser.trustedPublisher != null' <<<"$json")"

  if [[ "$version" == "$pin" ]]; then
    echo "  @playwright/cli $pin: still the latest release, pin is a no-op"
  elif [[ "$trusted" == "true" ]]; then
    echo "  @playwright/cli $pin: latest is $version and HAS a trusted publisher"
    action "restore \"npm:@playwright/cli\" = \"latest\" in mise/.config/mise/config.toml"
  else
    echo "  @playwright/cli $pin: latest is $version, still no trusted publisher, keep the pin"
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

# Advisory: a stale pin is a report, never a failed update.
exit 0
