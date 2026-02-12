#!/usr/bin/env bash
set -euo pipefail

# macos-bootstrap.sh
# Configures macOS system preferences. Some changes may require log out/in to fully apply.

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1" >&2; exit 1; }; }
need_cmd defaults
need_cmd /usr/bin/python3
need_cmd killall
need_cmd softwareupdate

# Ask for admin once up front (used by Firewall, FileVault, Rosetta, and Spotlight mds refresh).
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  sudo -v
fi

###############################################################################
# Trackpad
###############################################################################

echo "Trackpad: Enable tap to click"
defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
defaults write NSGlobalDomain com.apple.mouse.tapBehavior -int 1

echo "Trackpad: Enable three-finger drag"
defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag -bool true
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerDrag -bool true
# Disable other dragging modes (mutually exclusive)
defaults write com.apple.AppleMultitouchTrackpad Dragging -bool false
defaults write com.apple.AppleMultitouchTrackpad DragLock -bool false
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Dragging -bool false
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad DragLock -bool false

###############################################################################
# Keyboard
###############################################################################

echo "Keyboard: Disable automatic capitalization"
defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false

###############################################################################
# Finder
###############################################################################

echo "Finder: Show all filename extensions"
defaults write NSGlobalDomain AppleShowAllExtensions -bool true

echo "Finder: Show path bar"
defaults write com.apple.finder ShowPathbar -bool true

echo "Finder: New windows show Downloads"
defaults write com.apple.finder NewWindowTarget -string "PfLo"
defaults write com.apple.finder NewWindowTargetPath -string "file://${HOME}/Downloads/"

echo "Finder: Disable recent tags in sidebar"
defaults write com.apple.finder ShowRecentTags -bool false

echo "Finder: Disable extension change warning"
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false

echo "Finder: Search current folder by default"
defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"

###############################################################################
# Dock
###############################################################################

echo "Dock: Hide recent applications"
defaults write com.apple.dock show-recents -bool false

###############################################################################
# Screen Saver & Lock
###############################################################################

echo "Screen Saver: Start after 5 minutes"
defaults write com.apple.screensaver idleTime -int 300

echo "Screen Saver: Require password immediately"
defaults write com.apple.screensaver askForPassword -int 1
defaults write com.apple.screensaver askForPasswordDelay -int 0

###############################################################################
# Spotlight
###############################################################################

echo "Spotlight: Disable all categories except Applications, Calculator, System Settings"
python3 - <<'PY'
import plistlib, subprocess, sys

def run(*args, input_bytes=None):
    p = subprocess.run(args, input=input_bytes, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if p.returncode != 0:
        sys.stderr.write(p.stderr.decode("utf-8", "ignore"))
        raise SystemExit(p.returncode)
    return p.stdout

domain = "com.apple.Spotlight"

data = run("defaults", "export", domain, "-")
pl = plistlib.loads(data)

items = pl.get("orderedItems")
if not isinstance(items, list):
    sys.stderr.write("Spotlight orderedItems not found; skipping Spotlight category changes.\n")
    raise SystemExit(0)

keep_tokens = {
    "APPLICATIONS",
    "APP",
    "CALCULATOR",
    "SYSTEM_PREFS",
    "SYSTEMPREFERENCES",
    "SYSTEM_PREFERENCES",
    "SYSTEM_SETTINGS",
    "PREFERENCES",
}

def should_keep(name: str) -> bool:
    u = (name or "").upper()
    return any(tok in u for tok in keep_tokens)

for it in items:
    if isinstance(it, dict) and "name" in it:
        it["enabled"] = bool(should_keep(str(it.get("name",""))))

pl["orderedItems"] = items
out = plistlib.dumps(pl, fmt=plistlib.FMT_XML)
run("defaults", "import", domain, "-", input_bytes=out)
PY

###############################################################################
# Security
###############################################################################

echo "Security: Enable Firewall"
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on >/dev/null

echo "Security: Enable FileVault"
if sudo fdesetup status | grep -qi "FileVault is On"; then
  echo "  FileVault already enabled."
else
  sudo fdesetup enable
fi

###############################################################################
# System
###############################################################################

echo "System: Install Rosetta 2"
sudo softwareupdate --install-rosetta --agree-to-license || true

###############################################################################
# Apply Changes
###############################################################################

echo "Applying changes..."
killall cfprefsd 2>/dev/null || true
killall Dock 2>/dev/null || true
killall Finder 2>/dev/null || true
sudo killall mds 2>/dev/null || true

if [[ -x /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings ]]; then
  /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u 2>/dev/null || true
fi

echo "Done."
echo "Note: Trackpad and Spotlight changes may require log out/in to fully apply."
