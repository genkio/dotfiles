#!/usr/bin/env bash
set -euo pipefail

# macos-bootstrap.sh
# Configures macOS system preferences. Some changes may require log out/in to fully apply.

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1" >&2; exit 1; }; }
need_cmd defaults
need_cmd /usr/bin/python3
need_cmd killall
need_cmd pmset
need_cmd nvram
need_cmd softwareupdate

# Some preference domains drift across macOS releases; warn instead of aborting.
optional() {
  if "$@" >/dev/null 2>&1; then
    return 0
  fi

  printf '  Skipping: %s\n' "$*"
  return 0
}

defaults_write() {
  optional defaults write "$@"
}

defaults_current_host_write() {
  optional defaults -currentHost write "$@"
}

# Ask for admin once up front (used by Firewall, FileVault, Rosetta, and Spotlight mds refresh).
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  sudo -v
fi

###############################################################################
# Trackpad
###############################################################################

echo "Trackpad: Enable tap to click"
defaults_write com.apple.AppleMultitouchTrackpad Clicking -bool true
defaults_write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
defaults_current_host_write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
defaults_write NSGlobalDomain com.apple.mouse.tapBehavior -int 1

echo "Trackpad: Enable three-finger drag"
defaults_write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag -bool true
defaults_write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerDrag -bool true
# Disable other dragging modes (mutually exclusive)
defaults_write com.apple.AppleMultitouchTrackpad Dragging -bool false
defaults_write com.apple.AppleMultitouchTrackpad DragLock -bool false
defaults_write com.apple.driver.AppleBluetoothMultitouch.trackpad Dragging -bool false
defaults_write com.apple.driver.AppleBluetoothMultitouch.trackpad DragLock -bool false

###############################################################################
# Keyboard
###############################################################################

echo "Keyboard: Disable automatic capitalization"
defaults_write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false

###############################################################################
# Accessibility
###############################################################################

echo "Accessibility: Enable Reduce motion"
defaults_write com.apple.universalaccess reduceMotion -bool true

###############################################################################
# Sound
###############################################################################

echo "Sound: Mute output by default"
osascript -e "set volume with output muted"

echo "Sound: Always show volume icon in menu bar"
defaults_write com.apple.controlcenter "NSStatusItem Visible Sound" -bool true
defaults_current_host_write com.apple.controlcenter Sound -int 18

echo "Sound: Disable startup sound"
if sudo nvram StartupMute=%01 >/dev/null 2>&1; then
  :
else
  echo "  Skipping: could not set StartupMute NVRAM flag"
fi

###############################################################################
# Finder
###############################################################################

echo "Finder: Show all filename extensions"
defaults_write NSGlobalDomain AppleShowAllExtensions -bool true

echo "Finder: Show path bar"
defaults_write com.apple.finder ShowPathbar -bool true

echo "Finder: Show status bar"
defaults_write com.apple.finder ShowStatusBar -bool true

echo "Finder: Use list view by default"
defaults_write com.apple.finder FXPreferredViewStyle -string "Nlsv"

echo "Finder: Show Hard disks in sidebar Locations"
defaults_write com.apple.finder disksEnabled -bool true
defaults_write com.apple.finder SidebarDevicesSectionDisclosedState -bool true

echo "Finder: Hide Recent from sidebar Favorites"
defaults_write com.apple.finder recentsEnabled -bool false

echo "Finder: New windows show Downloads"
defaults_write com.apple.finder NewWindowTarget -string "PfLo"
defaults_write com.apple.finder NewWindowTargetPath -string "file://${HOME}/Downloads/"

echo "Finder: Disable recent tags in sidebar"
defaults_write com.apple.finder ShowRecentTags -bool false

echo "Finder: Disable extension change warning"
defaults_write com.apple.finder FXEnableExtensionChangeWarning -bool false

echo "Finder: Search current folder by default"
defaults_write com.apple.finder FXDefaultSearchScope -string "SCcf"

###############################################################################
# Dock
###############################################################################

echo "Dock: Hide recent applications"
defaults_write com.apple.dock show-recents -bool false

echo "Dock: Remove all apps, keep app launcher and Terminal"
python3 - <<'PY'
import plistlib
import os
import subprocess

dock_plist = os.path.expanduser("~/Library/Preferences/com.apple.dock.plist")

# Read current plist
data = subprocess.run(["defaults", "export", "com.apple.dock", "-"], capture_output=True, check=True)
pl = plistlib.loads(data.stdout)

# App launcher: Launchpad (pre-Tahoe) or Apps (Tahoe+)
app_launcher = None
for launcher in ["/System/Applications/Apps.app", "/System/Applications/Launchpad.app"]:
    if os.path.exists(launcher):
        app_launcher = launcher
        break

# Apps to add (Finder is always first, no need to add)
candidate_apps = [
    app_launcher,
    "/System/Applications/Utilities/Terminal.app",
]
apps = [app for app in candidate_apps if app and os.path.exists(app)]

def make_dock_entry(path):
    return {
        "tile-data": {
            "file-data": {
                "_CFURLString": path,
                "_CFURLStringType": 0,
            }
        }
    }

pl["persistent-apps"] = [make_dock_entry(app) for app in apps]

# Write back
out = plistlib.dumps(pl, fmt=plistlib.FMT_XML)
subprocess.run(["defaults", "import", "com.apple.dock", "-"], input=out, check=True)
PY

###############################################################################
# Screen Saver & Lock
###############################################################################

echo "Screen Saver: Start after 5 minutes"
defaults_write com.apple.screensaver idleTime -int 300

echo "Screen Saver: Require password immediately"
defaults_write com.apple.screensaver askForPassword -int 1
defaults_write com.apple.screensaver askForPasswordDelay -int 0

echo "Hot Corners: Bottom-left to Lock Screen"
defaults_write com.apple.dock wvous-bl-corner -int 13
defaults_write com.apple.dock wvous-bl-modifier -int 0

echo "Hot Corners: Upper-right to Notification Center"
defaults_write com.apple.dock wvous-tr-corner -int 12
defaults_write com.apple.dock wvous-tr-modifier -int 0

###############################################################################
# Power
###############################################################################

echo "Power: Disable system sleep (AC and battery)"
sudo pmset -a sleep 0

echo "Power: Disable Power Nap (AC and battery)"
sudo pmset -a powernap 0

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
# Desktop Background
###############################################################################

echo "Desktop: Set solid black background"
BLACK_PNG="/System/Library/Desktop Pictures/Solid Colors/Black.png"
if [[ -f "$BLACK_PNG" ]]; then
  osascript -e "tell application \"System Events\" to tell every desktop to set picture to \"$BLACK_PNG\""
else
  echo "  Skipping: $BLACK_PNG not found"
fi

###############################################################################
# Security
###############################################################################

echo "Security: Enable Firewall"
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on >/dev/null

###############################################################################
# System
###############################################################################

echo "System: Install Rosetta 2"
sudo softwareupdate --install-rosetta --agree-to-license || true

echo "Menu Bar: Reduce item spacing"
defaults_current_host_write -globalDomain NSStatusItemSpacing -int 2
defaults_current_host_write -globalDomain NSStatusItemSelectionPadding -int 2

###############################################################################
# Apply Changes
###############################################################################

echo "Applying changes..."
killall cfprefsd 2>/dev/null || true
killall ControlCenter 2>/dev/null || true
killall Dock 2>/dev/null || true
killall Finder 2>/dev/null || true
sudo killall mds 2>/dev/null || true

if [[ -x /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings ]]; then
  /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u 2>/dev/null || true
fi

echo "Security: Enable FileVault"
if sudo fdesetup isactive >/dev/null 2>&1; then
  echo "  FileVault already active; skipping enable."
else
  sudo fdesetup enable
fi

echo "Done."
echo "Note: Trackpad and Spotlight changes may require log out/in to fully apply."
