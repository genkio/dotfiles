#!/usr/bin/env bash
set -euo pipefail

# Provision Sublime Text headlessly (no GUI console):
#   1. Drop `Package Control.sublime-package` into Installed Packages/ so
#      "Package Control: Install Package" works on first launch.
#   2. Seed/merge `installed_packages` into User settings; Package Control
#      installs any listed-but-missing package on launch.
#   3. Set Sublime as the default opener for text + code files, without the
#      pile of Finder confirmation dialogs `duti -s` triggers (see below).
# The settings file is seeded, not stowed (like ~/.codex/config.toml): Package
# Control rewrites it at runtime (bootstrapped flag, in_process_packages,
# GUI-added packages), so a symlink into the repo would churn. Re-run to push
# newly-curated packages or file associations.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib.sh"
SOURCE_FILE="$REPO_ROOT/sublime/Package Control.sublime-settings"

APP="/Applications/Sublime Text.app"
DATA_DIR="$HOME/Library/Application Support/Sublime Text"
INSTALLED_PACKAGES_DIR="$DATA_DIR/Installed Packages"
USER_DIR="$DATA_DIR/Packages/User"
TARGET_FILE="$USER_DIR/Package Control.sublime-settings"
PC_PACKAGE="$INSTALLED_PACKAGES_DIR/Package Control.sublime-package"
PC_URL="https://packagecontrol.io/Package%20Control.sublime-package"
ASSOC_FILE="$REPO_ROOT/sublime/file-associations.txt"
LS_DOMAIN="com.apple.LaunchServices/com.apple.launchservices.secure"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null || echo com.sublimetext.4)"

PY="$(command -v python3 || true)"
if [[ -z "$PY" && -x /usr/bin/python3 ]]; then
  PY=/usr/bin/python3
fi

if [[ ! -f "$SOURCE_FILE" ]]; then
  err "Sublime settings baseline not found at $SOURCE_FILE"
  exit 1
fi

# Cask not installed and app never launched: nothing to configure.
if [[ ! -d "$APP" && ! -d "$DATA_DIR" ]]; then
  echo "Sublime Text not installed; skipping Package Control setup."
  exit 0
fi

# Non-fatal: a network hiccup shouldn't abort provisioning, and the seeded list
# below still applies once Package Control is present (later re-run, or the
# command palette).
mkdir -p "$INSTALLED_PACKAGES_DIR"
if [[ -f "$PC_PACKAGE" ]]; then
  echo "Package Control already bootstrapped."
else
  tmp="$PC_PACKAGE.tmp.$$"
  if curl -fsSL "$PC_URL" -o "$tmp"; then
    mv -f "$tmp" "$PC_PACKAGE"
    echo "Bootstrapped Package Control into Installed Packages/."
  else
    rm -f "$tmp"
    warn "could not download Package Control from $PC_URL; skipping bootstrap."
  fi
fi

# A bare extension only has a real UTI when some installed app declares it;
# anything else resolves to a throwaway `dyn.*` type that no handler preference
# can attach to. Resolving here keeps those out of the change list rather than
# asking LaunchServices to record something it will ignore.
resolve_extension_utis() {
  (($#)) || return 0
  if ! command -v swift >/dev/null 2>&1; then
    warn "swift not found; ignoring the bare extensions in $ASSOC_FILE."
    warn "Install the Xcode command line tools, or list UTIs instead."
    return 0
  fi
  swift - "$@" <<'SWIFT'
import Foundation
import UniformTypeIdentifiers

for ext in CommandLine.arguments.dropFirst() {
    guard let type = UTType(filenameExtension: ext), !type.identifier.hasPrefix("dyn.") else { continue }
    print(type.identifier)
}
SWIFT
}

# Round-trips the whole domain through cfprefsd (`defaults export`/`import`)
# rather than editing com.apple.launchservices.secure.plist in place: the
# daemon caches the domain and would flush its copy back over a direct write.
write_ls_handlers() {
  local rc=0 exported updated
  exported="$(mktemp -t ls-handlers-in)"
  updated="$(mktemp -t ls-handlers-out)"

  if ! defaults export "$LS_DOMAIN" - >"$exported"; then
    rm -f "$exported" "$updated"
    return 1
  fi

  "$PY" - "$exported" "$updated" "$BUNDLE_ID" "$@" <<'PYEOF' || rc=$?
import plistlib
import sys
import time

exported, updated, bundle_id = sys.argv[1], sys.argv[2], sys.argv[3]

with open(exported, "rb") as f:
    domain = plistlib.load(f)

handlers = domain.get("LSHandlers") or []
# Entries bind by content type, URL scheme, or filename tag; only the
# content-type ones are ours. Reuse an existing entry instead of appending a
# second one for the same UTI - LaunchServices picks between duplicates
# arbitrarily.
by_type = {h.get("LSHandlerContentType"): h for h in handlers if isinstance(h, dict)}
# LaunchServices timestamps count seconds from 2001-01-01, not the Unix epoch.
stamp = int(time.time() - 978307200)

for uti in sys.argv[4:]:
    entry = by_type.get(uti)
    if entry is None:
        entry = {"LSHandlerContentType": uti}
        handlers.append(entry)
        by_type[uti] = entry
    entry["LSHandlerRoleAll"] = bundle_id
    entry["LSHandlerPreferredVersions"] = {"LSHandlerRoleAll": "-"}
    entry["LSHandlerModificationDate"] = stamp

domain["LSHandlers"] = handlers
with open(updated, "wb") as f:
    plistlib.dump(domain, f)
PYEOF

  if ((rc == 0)); then
    defaults import "$LS_DOMAIN" "$updated" || rc=$?
  fi

  rm -f "$exported" "$updated"
  return "$rc"
}

desired_utis() {
  local token
  local -a exts=()
  while IFS= read -r token || [[ -n "$token" ]]; do
    token="${token%%#*}"
    token="${token//[[:space:]]/}"
    [[ -z "$token" ]] && continue
    if [[ "$token" == *.* ]]; then
      printf '%s\n' "$token"
    else
      exts+=("$token")
    fi
  done < "$ASSOC_FILE"
  resolve_extension_utis ${exts[@]+"${exts[@]}"}
}

# macOS makes the user confirm every default-handler change that goes through
# LaunchServices, and `duti -s` is one such call per type: a fresh machine used
# to stack ~30 modal Finder dialogs over the terminal, and re-running re-asked
# for types that were already set. So read the current handler first and only
# touch what actually differs, then write those through cfprefsd and restart
# lsd, which applies them silently. duti is now read-only here.
if [[ -f "$ASSOC_FILE" ]]; then
  if ! command -v duti >/dev/null 2>&1; then
    warn "duti not found; skipping default-opener setup (it's in brew/Brewfile.apps)."
    warn "Install it, then re-run 'make sublime'."
  elif [[ -z "$PY" ]]; then
    warn "python3 not found; skipping default-opener setup."
  else
    pending=()
    while IFS= read -r uti; do
      [[ -z "$uti" ]] && continue
      [[ "$(duti -d "$uti" 2>/dev/null)" == "$BUNDLE_ID" ]] && continue
      pending+=("$uti")
    done < <(desired_utis | sort -u)

    if ((${#pending[@]} == 0)); then
      echo "Default opener: already $BUNDLE_ID for every type in $ASSOC_FILE."
    elif write_ls_handlers "${pending[@]}"; then
      # lsd caches the handler table in memory and only re-reads the domain on
      # start, so the import is invisible until it restarts. launchd brings it
      # straight back.
      killall lsd 2>/dev/null || true
      echo "Default opener: set $BUNDLE_ID for ${#pending[@]} type(s): ${pending[*]}"
    else
      warn "could not update the LaunchServices handler table; default opener unchanged."
    fi
  fi
fi

mkdir -p "$USER_DIR"
if [[ ! -f "$TARGET_FILE" ]]; then
  cp "$SOURCE_FILE" "$TARGET_FILE"
  echo "Seeded $TARGET_FILE"
  echo "On first launch, Package Control bootstraps itself and may ask to restart"
  echo "Sublime (one-time dependency migration). Quit and reopen once; the listed"
  echo "packages then install automatically."
  exit 0
fi

# Target exists and is runtime-managed by Package Control (trailing commas, its
# own keys). Union the curated list in without clobbering GUI-added packages.
if [[ -z "$PY" ]]; then
  warn "python3 not found; left existing $TARGET_FILE untouched."
  warn "Add any missing packages from $SOURCE_FILE by hand."
  exit 0
fi

# Sublime settings are JSON with comments + trailing commas, which the stdlib
# json parser rejects; strip both (string-aware) before parsing, union the
# lists, and write back only when something is actually missing.
"$PY" - "$SOURCE_FILE" "$TARGET_FILE" <<'PYEOF' || warn "Package Control merge failed; left settings untouched."
import io, json, sys

def strip_comments(text):
    out, i, n = [], 0, len(text)
    in_str = esc = False
    while i < n:
        c = text[i]
        if in_str:
            out.append(c)
            if esc: esc = False
            elif c == "\\": esc = True
            elif c == '"': in_str = False
            i += 1; continue
        if c == '"':
            in_str = True; out.append(c); i += 1; continue
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            i += 2
            while i < n and text[i] != "\n": i += 1
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "*":
            i += 2
            while i + 1 < n and not (text[i] == "*" and text[i + 1] == "/"): i += 1
            i += 2; continue
        out.append(c); i += 1
    return "".join(out)

def drop_trailing_commas(text):
    out, i, n = [], 0, len(text)
    in_str = esc = False
    while i < n:
        c = text[i]
        if in_str:
            out.append(c)
            if esc: esc = False
            elif c == "\\": esc = True
            elif c == '"': in_str = False
            i += 1; continue
        if c == '"':
            in_str = True; out.append(c); i += 1; continue
        if c == ",":
            j = i + 1
            while j < n and text[j] in " \t\r\n": j += 1
            if j < n and text[j] in "}]":
                i += 1; continue
        out.append(c); i += 1
    return "".join(out)

def load(path):
    with io.open(path, encoding="utf-8") as f:
        return json.loads(drop_trailing_commas(strip_comments(f.read())))

source, target = sys.argv[1], sys.argv[2]
try:
    want = load(source).get("installed_packages", [])
    data = load(target)
except Exception as e:
    sys.stderr.write("SETUP_WARN: Package Control could not parse settings (%s); left untouched.\n" % e)
    sys.exit(0)

have = data.get("installed_packages", [])
missing = [p for p in want if p not in have]
if not missing:
    print("Package Control: installed_packages already current; no changes.")
    sys.exit(0)

data["installed_packages"] = have + missing
with io.open(target, "w", encoding="utf-8") as f:
    f.write(json.dumps(data, indent="\t", ensure_ascii=False) + "\n")
print("Package Control: added " + ", ".join(missing) + " to installed_packages.")
print("Restart Sublime Text to install them.")
PYEOF
