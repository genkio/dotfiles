#!/usr/bin/env bash
set -euo pipefail

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

if [[ ! -d "$APP" && ! -d "$DATA_DIR" ]]; then
  echo "Sublime Text not installed; skipping Package Control setup."
  exit 0
fi

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
by_type = {h.get("LSHandlerContentType"): h for h in handlers if isinstance(h, dict)}
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

if [[ -z "$PY" ]]; then
  warn "python3 not found; left existing $TARGET_FILE untouched."
  warn "Add any missing packages from $SOURCE_FILE by hand."
  exit 0
fi

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
