#!/usr/bin/env bash
#
# Install upstream prebuilt binaries for the formulae that Homebrew can no
# longer bottle for Intel macs.
#
# homebrew-core stopped building macOS x86_64 bottles, and `go` and `rust` are
# among the formulae with none left. So a single Go or Rust CLI (yazi, fzf, gh,
# mise, ...) drags in rustc or the Go toolchain from source, and rustc drags in
# llvm: hours of compiling for a 3 MB binary. Every tool here publishes a
# darwin-amd64 build of its own, which installs in seconds.
#
# The formulae are guarded with `if on_silicon` in the Brewfiles, so brew never
# sees them on Intel and this script is the only installer. On Apple Silicon
# nothing changes: the bottles are there and this script refuses to run.
#
# Handled elsewhere, not dropped:
#   tailscale   no CLI tarball for macOS, so Brewfile.base installs the signed
#               universal pkg (cask "tailscale-app") on Intel instead
#   tmux, mpv   C builds whose deps are all bottled, so brew handles them fine
#
# Pins live in intel-prebuilt.tsv: a version and the sha256 of that exact
# artifact, the same tradeoff as install-alacritty.sh - these are release
# tarballs with no signature, so content integrity stands in for publisher
# identity, and a hash only means something against a fixed version.
#
# Usage:
#   install-intel-prebuilt.sh base        install the base set at the pins
#   install-intel-prebuilt.sh dev         install the dev set at the pins
#   install-intel-prebuilt.sh             reinstall pins that drifted, nothing new
#   install-intel-prebuilt.sh --upgrade   follow upstream and rewrite the pins
#   ... --dry-run                         report, touch nothing

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

MANIFEST="$SCRIPT_DIR/intel-prebuilt.tsv"

# ~/.local/bin, not brew's prefix: a non-brew symlink in there trips
# `brew doctor`, and .zshrc puts ~/.local/bin first on PATH. Trees live beside
# it under ~/.local/opt because some of these are not lone binaries - nvim needs
# its runtime/ next to the executable, gh and mise ship man pages.
OPT_DIR="$HOME/.local/opt"
BIN_DIR="$HOME/.local/bin"

WANT_SET=""
DRY_RUN=0
UPGRADE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    base|dev) WANT_SET="$1" ;;
    --dry-run|-n) DRY_RUN=1 ;;
    --upgrade|-u) UPGRADE=1 ;;
    -h|--help)
      echo "Usage: $(basename "$0") [base|dev] [--upgrade|-u] [--dry-run|-n]"
      echo "  base, dev   install that set; omit to reinstall drifted pins only"
      echo "  --upgrade   take the newest compatible release unless policy is pinned"
      exit 0
      ;;
    *) err "unknown option: $1"; exit 1 ;;
  esac
  shift
done

# DOTFILES_FORCE_PREBUILT exists so the manifest can be exercised on an Apple
# Silicon machine (download, checksum, archive layout). The binaries it installs
# are x86_64 and will not run there.
if [[ "$(/usr/bin/uname -m)" == "arm64" && -z "${DOTFILES_FORCE_PREBUILT:-}" ]]; then
  echo "Apple Silicon: Homebrew bottles cover these tools, nothing to do."
  exit 0
fi

if [[ ! -f "$MANIFEST" ]]; then
  err "manifest not found: $MANIFEST"
  exit 1
fi

FAILURES=()
fail_tool() {
  warn "$1: $2"
  FAILURES+=("$1")
}

installed_version() { cat "$OPT_DIR/$1/.version" 2>/dev/null; }

# {v} -> 26.03, {vnd} -> 2603 (7-Zip names its archives after the latter).
expand() {
  local template="$1" version="$2"
  template="${template//\{v\}/$version}"
  template="${template//\{vnd\}/${version//./}}"
  printf '%s' "$template"
}

asset_url() {
  local repo="$1" tag_tmpl="$2" version="$3" asset_tmpl="$4"
  printf 'https://github.com/%s/releases/download/%s/%s' \
    "$repo" "$(expand "$tag_tmpl" "$version")" "$(expand "$asset_tmpl" "$version")"
}

# Newest non-prerelease tag that still publishes the configured Intel asset,
# stripped of its v/V prefix. This matters for tools such as lnav: newer
# releases exist, but upstream stopped publishing x86_64 macOS builds. Empty on
# any failure, which callers read as "stay on the pin" - a rate-limited API or
# a dropped network must never look like a downgrade.
latest_version() {
  local repo="$1" asset_tmpl="$2"
  curl -fsSL --max-time 20 \
    "https://api.github.com/repos/$repo/releases?per_page=100" 2>/dev/null |
    /usr/bin/python3 -c 'import json,sys
template = sys.argv[1]
try:
    releases = json.load(sys.stdin)
except Exception:
    releases = []
for release in releases:
    if release.get("draft") or release.get("prerelease"):
        continue
    tag = release.get("tag_name", "")
    version = tag[1:] if tag[:1] in ("v", "V") else tag
    asset = template.replace("{v}", version).replace("{vnd}", version.replace(".", ""))
    if any(item.get("name") == asset for item in release.get("assets", [])):
        print(version)
        break' "$asset_tmpl" 2>/dev/null
}

# Extract into a staging dir, then hoist a lone top-level directory out of the
# way, so nvim-macos-x86_64/bin/nvim and a flat lazygit both end up as
# <tree>/<binary path from the manifest>.
extract_into() {
  local archive="$1" dest="$2" entries=()

  case "$archive" in
    *.zip) unzip -q "$archive" -d "$dest" || return 1 ;;
    *) tar xf "$archive" -C "$dest" || return 1 ;;
  esac

  entries=("$dest"/*)
  if [[ "${#entries[@]}" -eq 1 && -d "${entries[0]}" ]]; then
    # A hidden file at the top level would be left behind by a plain glob move,
    # so rename the inner dir instead of copying out of it.
    mv "${entries[0]}" "$dest.inner" && rm -rf "$dest" && mv "$dest.inner" "$dest"
  fi
}

# sha256 of what was actually installed, so --upgrade can write it back as the
# new pin. Set by install_tool on success.
INSTALLED_SHA=""

# $4 is the expected sha256, or "-" to accept whatever downloads and report its
# hash instead (--upgrade, where there is no pin for the new version yet).
install_tool() {
  local name="$1" version="$2" url="$3" sha256="$4" binaries="$5"
  local tree="$OPT_DIR/$name" tmp archive bin got

  INSTALLED_SHA=""
  tmp="$(mktemp -d)" || { fail_tool "$name" "mktemp failed"; return 1; }
  # shellcheck disable=SC2064  # $tmp must expand now, not at trap time
  trap "rm -rf '$tmp'" RETURN

  # Keep the upstream filename: extract_into picks tar vs unzip off the suffix.
  archive="$tmp/${url##*/}"
  if ! curl -fsSL "$url" -o "$archive"; then
    fail_tool "$name" "download failed: $url"
    return 1
  fi

  got="$(shasum -a 256 "$archive" | cut -d' ' -f1)"
  if [[ "$sha256" != "-" && "$got" != "$sha256" ]]; then
    fail_tool "$name" "sha256 mismatch, refusing to install"
    return 1
  fi

  mkdir -p "$tmp/tree"
  if ! extract_into "$archive" "$tmp/tree"; then
    fail_tool "$name" "could not extract the archive"
    return 1
  fi

  # Check every symlink target before touching the installed tree, so a manifest
  # whose layout moved between releases fails without leaving a half-install.
  for bin in $binaries; do
    if [[ ! -f "$tmp/tree/$bin" ]]; then
      fail_tool "$name" "$bin is missing from the $version archive"
      return 1
    fi
  done

  mkdir -p "$OPT_DIR" "$BIN_DIR"
  rm -rf "$tree"
  mv "$tmp/tree" "$tree"
  echo "$version" >"$tree/.version"
  for bin in $binaries; do
    chmod +x "$tree/$bin"
    ln -sfn "$tree/$bin" "$BIN_DIR/$(basename "$bin")"
  done

  INSTALLED_SHA="$got"
  echo "  $name $version installed to $tree"
}

# Rewrite one record's version and sha256 columns. Via a temp file and mv: the
# manifest is read into memory up front, but an in-place truncate would still be
# the one edit that can lose the file if the run dies mid-write.
repin() {
  local name="$1" version="$2" sha256="$3" tmp
  tmp="$(mktemp)" || return 1
  /usr/bin/python3 - "$MANIFEST" "$tmp" "$name" "$version" "$sha256" <<'PY' || { rm -f "$tmp"; return 1; }
import sys
src, dst, name, version, sha = sys.argv[1:6]
out = []
for line in open(src):
    cols = line.rstrip("\n").split("|")
    if len(cols) == 8 and cols[1] == name:
        cols[4], cols[6] = version, sha
        line = "|".join(cols) + "\n"
    out.append(line)
open(dst, "w").writelines(out)
PY
  cat "$tmp" >"$MANIFEST" && rm -f "$tmp"
}

REPINNED=()
CHANGED=0

while IFS='|' read -r tool_set name repo tag_tmpl version asset_tmpl sha256 binaries upgrade_policy; do
  [[ -z "$tool_set" || "$tool_set" == \#* ]] && continue

  have="$(installed_version "$name")"
  if [[ -n "$WANT_SET" ]]; then
    [[ "$tool_set" == "$WANT_SET" ]] || continue
  else
    # Never introduce a tool this machine does not already have: same contract
    # as update.sh, which is the caller that runs without a set.
    [[ -n "$have" ]] || continue
  fi

  want="$version"
  pin_sha="$sha256"
  if [[ "$UPGRADE" == 1 && "$upgrade_policy" != "pinned" ]]; then
    latest="$(latest_version "$repo" "$asset_tmpl")"
    if [[ -z "$latest" ]]; then
      warn "$name: could not reach the GitHub release API, staying on $version"
    elif [[ "$latest" != "$version" ]]; then
      want="$latest"
      # No pin exists for a version nobody has seen yet, so the hash of what
      # downloads becomes the pin - trust-on-first-use over TLS, and every other
      # machine then verifies against it.
      pin_sha="-"
    fi
  fi

  # A stale pin still has to be rewritten even when this machine already runs the
  # newer build, or a repin that failed once would never be retried.
  [[ "$have" == "$want" && "$want" == "$version" ]] && continue

  if [[ "$DRY_RUN" == 1 ]]; then
    if [[ "$want" != "$version" ]]; then
      echo "  $name: $version pinned, upstream has $want (would install and repin)"
    else
      echo "  $name: would install $want over ${have:-nothing}"
    fi
    CHANGED=1
    continue
  fi

  CHANGED=1
  install_tool "$name" "$want" "$(asset_url "$repo" "$tag_tmpl" "$want" "$asset_tmpl")" \
    "$pin_sha" "$binaries" || continue

  if [[ "$want" != "$version" ]]; then
    if repin "$name" "$want" "$INSTALLED_SHA"; then
      REPINNED+=("$name $version -> $want")
    else
      fail_tool "$name" "installed $want but could not rewrite the pin in ${MANIFEST##*/}"
    fi
  fi
done <"$MANIFEST"

if [[ "${#REPINNED[@]}" -gt 0 ]]; then
  echo "  repinned in ${MANIFEST##*/}: ${REPINNED[*]}"
  echo "  commit it so the other machines get the same versions."
fi

[[ "$DRY_RUN" == 1 && "$CHANGED" == 1 ]] && echo
[[ "${#FAILURES[@]}" -gt 0 ]] && exit 1
exit 0
