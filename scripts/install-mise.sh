#!/usr/bin/env bash
#
# Install mise from its own installer instead of the Homebrew formula.
#
# mise is a Rust program and `brew install mise` lists llvm and rust as build
# deps. Homebrew moved Intel macOS to Tier 3 and stopped building x86_64 bottles
# (docs.brew.sh/Support-Tiers; Intel support removed September 2027 or later),
# so on an Intel Mac that formula compiles LLVM 23, LLVM 22 and rustc before it
# ever reaches mise - hours of build for a tool that ships a prebuilt
# x86_64-apple-darwin binary.
#
# No pinned sha256 here, unlike install-alacritty.sh and install-fliqlo.sh:
# mise.run resolves the current release and verifies it against the
# SHASUMS256.txt published alongside it, so a local pin would only freeze the
# version without adding a check. Same trust model as the Claude Code installer
# in setup-dev.sh.
#
# Lands in ~/.local/bin, which zsh/.zshrc already puts ahead of Homebrew on
# PATH, so this wins over a leftover `brew install mise` on an existing machine.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

BIN="$HOME/.local/bin/mise"

installed_version() {
  [[ -x "$BIN" ]] || return 1
  "$BIN" --version 2>/dev/null | awk '{print $1}'
}

if [[ "${1:-}" == "--dry-run" || "${1:-}" == "-n" ]]; then
  have="$(installed_version || true)"
  if [[ -n "$have" ]]; then
    echo "  mise: $have at $BIN, would install only if upstream is newer"
  else
    echo "  mise: would install the current release to $BIN"
  fi
  exit 0
fi

# The installer skips the download when $BIN already matches the release it
# resolved, so it needs no guard of its own. MISE_INSTALL_HELP=0 drops its
# "add this to your .zshrc" epilogue: the zsh package already activates mise.
curl -fsSL https://mise.run | MISE_INSTALL_HELP=0 sh
