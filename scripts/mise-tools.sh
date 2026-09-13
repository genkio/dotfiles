#!/usr/bin/env bash
#
# The repo's global mise tools: install the locked set, or maintain the lock.
#
# `mise/.config/mise/config.toml` declares the CLIs and language runtimes, and
# `mise.lock` records the exact version plus the per-platform artifact (URL,
# checksum, provenance) for both macos-arm64 and macos-x64. Every machine
# installs from that one file, so Intel and Apple Silicon run the same versions;
# MISE_LOCKED=1 makes mise fail instead of substituting something different when
# the current platform has no lock entry.
#
# Usage:
#   mise-tools.sh              install the locked set (idempotent)
#   mise-tools.sh --lock       re-resolve selectors and rewrite mise.lock
#   mise-tools.sh --upgrade    --lock with --bump, then install the new set
#   mise-tools.sh --check      report lock entries missing a macOS platform
#   --dry-run, -n              report what --lock/--upgrade would change
#
# The lock is read and written under the repo, not through ~/.config/mise, so
# the checkout is authoritative even on a machine that has not stowed the mise
# package yet. `make lock` runs --lock; update.sh runs --upgrade and --check.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib.sh"

CONFIG_DIR="$REPO_ROOT/mise/.config/mise"
CONFIG="$CONFIG_DIR/config.toml"
LOCK="$CONFIG_DIR/mise.lock"

MODE="install"
DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --lock) MODE="lock" ;;
    --upgrade) MODE="upgrade" ;;
    --check) MODE="check" ;;
    --dry-run|-n) DRY_RUN=1 ;;
    -h|--help)
      echo "Usage: $(basename "$0") [--lock|--upgrade|--check] [--dry-run|-n]"
      echo "  (no flags)  install the locked tool set"
      echo "  --lock      re-resolve selectors and rewrite mise.lock"
      echo "  --upgrade   --lock with --bump, then install the new set"
      echo "  --check     report lock entries missing a macOS platform"
      exit 0
      ;;
    *) err "unknown option: $1"; exit 1 ;;
  esac
  shift
done

# The flow may run before ~/.local/bin is on PATH (on Intel that is where the
# bootstrap puts mise), and brew's prefix is not in PATH of a fresh shell.
find_mise() {
  command -v mise >/dev/null 2>&1 && return 0
  local candidate
  for candidate in "$HOME/.local/bin/mise" /opt/homebrew/bin/mise /usr/local/bin/mise; do
    if [[ -x "$candidate" ]]; then
      export PATH="$(dirname "$candidate"):$PATH"
      return 0
    fi
  done
  err "mise is not installed; run 'make bootstrap' (or 'bash scripts/install-intel-prebuilt.sh bootstrap' on Intel) first."
  return 1
}

# Point mise at the checkout's config directory: config.toml and mise.lock are
# both read and written there, so the repo stays authoritative even on a machine
# that has not stowed the mise package yet. It also sidesteps the real
# ~/.config/mise tree entirely, which keeps `lock` from touching it.
mise_repo() {
  MISE_CONFIG_DIR="$CONFIG_DIR" mise "$@"
}

install_tools() {
  find_mise
  # Node first: the npm: tools (including pi) install through the configured
  # node, and a parallel bare install can reach them before node lands.
  MISE_LOCKED=1 mise_repo install --quiet node
  MISE_LOCKED=1 mise_repo install --quiet
  echo "mise: tools installed (locked to mise.lock)"
}

# Every tool that locks an artifact should have one for both architectures.
# npm tools have no artifact URL, so they are skipped; core:node/python/go/uv
# and every aqua tool do, and a missing macos-x64 entry is exactly "upstream
# dropped Intel", which MISE_LOCKED=1 then turns into a hard install failure.
check_lock() {
  [[ -f "$LOCK" ]] || {
    err "mise.lock not found; run scripts/mise-tools.sh --lock"
    return 1
  }
  awk '
    /^\[\[tools\./ {
      tool = $0
      sub(/^\[\[tools\./, "", tool)
      sub(/\]\].*$/, "", tool)
      gsub(/"/, "", tool)
      names[++n] = tool
      current = tool
      next
    }
    /platforms\.macos-/ {
      platform = $0
      sub(/.*platforms\./, "", platform)
      sub(/".*$/, "", platform)
      have[current, platform] = 1
    }
    END {
      missing = 0
      for (i = 1; i <= n; i++) {
        tool = names[i]
        arm = have[tool, "macos-arm64"]
        x64 = have[tool, "macos-x64"]
        if (!arm && !x64) continue
        if (arm && !x64) {
          printf "SETUP_WARN: %s: no macos-x64 artifact in mise.lock; upstream dropped Intel, so pin it to the last version that ships one\n", tool
          missing++
        } else if (x64 && !arm) {
          printf "SETUP_WARN: %s: no macos-arm64 artifact in mise.lock\n", tool
          missing++
        }
      }
      printf "mise.lock: %d tools, %d with a platform gap\n", n, missing
      exit missing > 0 ? 1 : 0
    }
  ' "$LOCK"
}

# MISE_CONFIG_DIR makes mise read and write both files in $CONFIG_DIR, so this
# needs no temp home and no symlink assumptions - whether the checkout is
# stowed or not, the lock lands in the repo.
run_lock() {
  local bump="$1" before after log
  local -a args=(lock -g)
  find_mise
  [[ "$bump" == "bump" ]] && args+=(--bump)
  [[ "$DRY_RUN" == 1 ]] && args+=(--dry-run)

  before="$(shasum -a 256 "$LOCK" 2>/dev/null | cut -d' ' -f1)"

  # A dry run writes into a scratch copy so the report is a real hash
  # comparison: mise's own "would update" list is printed even when nothing
  # would actually change.
  if [[ "$DRY_RUN" == 1 ]]; then
    local tmp after
    tmp="$(mktemp -d)"
    trap 'rm -r "$tmp" 2>/dev/null' RETURN
    cp "$CONFIG" "$tmp/config.toml"
    [[ -f "$LOCK" ]] && cp "$LOCK" "$tmp/mise.lock"
    if ! log="$(MISE_CONFIG_DIR="$tmp" mise "${args[@]}" 2>&1)"; then
      printf '%s\n' "$log"
      err "mise lock --dry-run failed."
      return 1
    fi
    after="$(shasum -a 256 "$tmp/mise.lock" 2>/dev/null | cut -d' ' -f1)"
    if [[ "$before" != "$after" ]]; then
      echo "mise: mise.lock would be updated"
    else
      echo "mise: mise.lock is current"
    fi
    return 0
  fi

  # Real run: MISE_CONFIG_DIR makes mise write both files in $CONFIG_DIR, so
  # the lock lands in the repo whether the checkout is stowed or not.
  if ! log="$(mise_repo "${args[@]}" 2>&1)"; then
    printf '%s\n' "$log"
    err "mise lock failed."
    return 1
  fi
  after="$(shasum -a 256 "$LOCK" | cut -d' ' -f1)"
  if [[ "$before" != "$after" ]]; then
    echo "mise: mise.lock updated"
  else
    echo "mise: mise.lock is current"
  fi
}

case "$MODE" in
  check) check_lock ;;
  lock) run_lock plain ;;
  upgrade)
    run_lock bump
    [[ "$DRY_RUN" == 1 ]] || install_tools
    ;;
  install) install_tools ;;
esac
