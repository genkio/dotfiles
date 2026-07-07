#!/usr/bin/env bash
set -euo pipefail

# Bootstrap Sublime Text's Package Control and seed the auto-installed package
# set, headlessly (no GUI console). Two moving parts:
#   1. Drop `Package Control.sublime-package` into Installed Packages/ so
#      "Package Control: Install Package" works on first launch.
#   2. Seed/merge `installed_packages` into User settings; Package Control
#      installs any listed-but-missing package on launch.
# Seeded, not stowed (like ~/.codex/config.toml): Package Control rewrites this
# file at runtime (bootstrapped flag, in_process_packages, GUI-added packages),
# so a symlink into the repo would churn. Re-run to push newly-curated packages.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
SOURCE_FILE="$REPO_ROOT/sublime/Package Control.sublime-settings"

APP="/Applications/Sublime Text.app"
DATA_DIR="$HOME/Library/Application Support/Sublime Text"
INSTALLED_PACKAGES_DIR="$DATA_DIR/Installed Packages"
USER_DIR="$DATA_DIR/Packages/User"
TARGET_FILE="$USER_DIR/Package Control.sublime-settings"
PC_PACKAGE="$INSTALLED_PACKAGES_DIR/Package Control.sublime-package"
PC_URL="https://packagecontrol.io/Package%20Control.sublime-package"

if [[ ! -f "$SOURCE_FILE" ]]; then
  echo "Sublime settings baseline not found at $SOURCE_FILE" >&2
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
    echo "Warning: could not download Package Control from $PC_URL; skipping bootstrap." >&2
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
PY="$(command -v python3 || true)"
if [[ -z "$PY" && -x /usr/bin/python3 ]]; then
  PY=/usr/bin/python3
fi
if [[ -z "$PY" ]]; then
  echo "python3 not found; left existing $TARGET_FILE untouched." >&2
  echo "Add any missing packages from $SOURCE_FILE by hand." >&2
  exit 0
fi

# Sublime settings are JSON with comments + trailing commas, which the stdlib
# json parser rejects; strip both (string-aware) before parsing, union the
# lists, and write back only when something is actually missing.
"$PY" - "$SOURCE_FILE" "$TARGET_FILE" <<'PYEOF' || echo "Warning: Package Control merge failed; left settings untouched." >&2
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
    sys.stderr.write("Package Control: could not parse settings (%s); left untouched.\n" % e)
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
