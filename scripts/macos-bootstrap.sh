#!/usr/bin/env bash
set -euo pipefail

# macOS defaults bootstrap for a new machine.
#
# This writes system and app preferences directly with `defaults`, `pmset`,
# `nvram`, and a few Apple utilities. It should be safe to rerun, but some
# settings require admin rights and some only become visible after logout,
# reboot, or the affected app restarting. Optional writes warn instead of
# aborting because macOS preference domains drift between releases.
#
# Pass --dry-run (-n) to print every mutation without executing it.

DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run|-n)
      DRY_RUN=1
      ;;
    -h|--help)
      echo "Usage: $(basename "$0") [--dry-run|-n]"
      echo "  --dry-run, -n  Print what would be written without making changes."
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
  shift
done

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1" >&2; exit 1; }; }
need_cmd defaults
need_cmd /usr/bin/python3
need_cmd killall
need_cmd pmset
need_cmd nvram
need_cmd softwareupdate
need_cmd sw_vers

# Captured once for any version-gated logic below.
MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "macOS major $MACOS_MAJOR detected (dry-run mode)"
else
  echo "macOS major $MACOS_MAJOR detected"
fi

# Tracks commands that failed under `optional` so the end of the run can
# surface them as a manual-followup list (e.g. settings Apple now restricts
# via TCC on macOS 26).
SKIPPED=()

# Run a command unless DRY_RUN=1, in which case just print it.
run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '  [dry-run] %s\n' "$*"
    return 0
  fi
  "$@"
}

# Some preference domains drift across macOS releases; warn instead of aborting.
optional() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '  [dry-run] %s\n' "$*"
    return 0
  fi

  if "$@" >/dev/null 2>&1; then
    return 0
  fi

  SKIPPED+=("$*")
  printf '  Skipping: %s\n' "$*"
  return 0
}

defaults_write() {
  optional defaults write "$@"
}

defaults_current_host_write() {
  optional defaults -currentHost write "$@"
}

# Wrapper that feeds the captured password to sudo via stdin. Needed because
# Homebrew's brew.sh resets the sudo timestamp on every invocation, so the
# cache may be cold by the time we get here. Falls back to plain sudo when
# no password is set (standalone invocation).
sudo_pw() {
  if [[ -n "${DOTFILES_SUDO_PASSWORD:-}" ]]; then
    printf '%s\n' "$DOTFILES_SUDO_PASSWORD" | sudo -S "$@"
  else
    sudo "$@"
  fi
}

# Ask for admin once up front (used by Firewall, FileVault, and Rosetta).
# Skip when invoked from opinionated-flow.sh, which already captured the
# password into DOTFILES_SUDO_PASSWORD; sudo_pw feeds it on every call.
if [[ "$DRY_RUN" -eq 0 && "${EUID:-$(id -u)}" -ne 0 && -z "${DOTFILES_SUDO_WARMED:-}" ]]; then
  sudo -v
  ( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) &
  SUDO_KEEPALIVE_PID=$!
  trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT
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

echo "Keyboard: Use F1, F2, etc. as standard function keys"
defaults_write NSGlobalDomain com.apple.keyboard.fnState -bool true

###############################################################################
# Accessibility
###############################################################################

# macOS 26 sandboxes com.apple.universalaccess via TCC, so these writes are
# typically rejected from a terminal process even with sudo. Failures land in
# the Skipped summary at the end — toggle them in System Settings →
# Accessibility → Display when needed.
echo "Accessibility: Enable Reduce motion"
defaults_write com.apple.universalaccess reduceMotion -bool true

echo "Accessibility: Enable Reduce transparency (clearer Liquid Glass on macOS 26+)"
defaults_write com.apple.universalaccess reduceTransparency -bool true

###############################################################################
# Sound
###############################################################################

echo "Sound: Mute output by default"
optional osascript -e "set volume with output muted"

echo "Sound: Always show volume icon in menu bar"
defaults_write com.apple.controlcenter "NSStatusItem Visible Sound" -bool true
defaults_current_host_write com.apple.controlcenter Sound -int 18

echo "Sound: Disable startup sound"
if [[ "$DRY_RUN" -eq 1 ]]; then
  printf '  [dry-run] %s\n' 'sudo nvram StartupMute=%01'
elif ! sudo_pw nvram StartupMute=%01 >/dev/null 2>&1; then
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

echo "Dock: Remove all apps, keep app launcher and System Settings"
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "  [dry-run] would rewrite com.apple.dock persistent-apps via Python plist mutation"
else
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
    "/System/Applications/System Settings.app",
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
fi

###############################################################################
# Screen Saver & Lock
###############################################################################

# Screen saver preferences moved to the per-host (ByHost) domain in macOS 14;
# user-domain writes are silently ignored on Sonoma+ and Tahoe.
echo "Screen Saver: Disable (never start)"
defaults_current_host_write com.apple.screensaver idleTime -int 0

echo "Screen Saver: Require password immediately"
defaults_current_host_write com.apple.screensaver askForPassword -int 1
defaults_current_host_write com.apple.screensaver askForPasswordDelay -int 0

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
optional sudo_pw pmset -a sleep 0

echo "Power: Disable display sleep (AC and battery)"
optional sudo_pw pmset -a displaysleep 0

echo "Power: Disable Power Nap (AC and battery)"
optional sudo_pw pmset -a powernap 0

###############################################################################
# Desktop Background
###############################################################################

echo "Desktop: Set solid black background"
BLACK_PNG="/System/Library/Desktop Pictures/Solid Colors/Black.png"
if [[ -f "$BLACK_PNG" ]]; then
  # The wallpaper subsystem has been unreliable on Tahoe (26.x); tolerate failure
  # so the rest of bootstrap still completes — set it manually if it skips.
  optional osascript -e "tell application \"System Events\" to tell every desktop to set picture to \"$BLACK_PNG\""
else
  echo "  Skipping: $BLACK_PNG not found"
fi

###############################################################################
# Security
###############################################################################

echo "Security: Enable Firewall"
if [[ "$DRY_RUN" -eq 1 ]]; then
  printf '  [dry-run] %s\n' 'sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on'
else
  sudo_pw /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on >/dev/null
fi

###############################################################################
# System
###############################################################################

echo "System: Install Rosetta 2"
run sudo_pw softwareupdate --install-rosetta --agree-to-license || true

echo "Menu Bar: Reduce item spacing"
defaults_current_host_write -globalDomain NSStatusItemSpacing -int 2
defaults_current_host_write -globalDomain NSStatusItemSelectionPadding -int 2

###############################################################################
# Apply Changes
###############################################################################

echo "Applying changes..."
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "  [dry-run] would killall cfprefsd, ControlCenter, Dock, Finder; activateSettings -u"
else
  killall cfprefsd 2>/dev/null || true
  killall ControlCenter 2>/dev/null || true
  killall Dock 2>/dev/null || true
  killall Finder 2>/dev/null || true

  if [[ -x /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings ]]; then
    /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u 2>/dev/null || true
  fi
fi

echo "Security: Enable FileVault"
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "  [dry-run] would check fdesetup isactive and run 'sudo fdesetup enable' if not active"
elif sudo_pw fdesetup isactive >/dev/null 2>&1; then
  echo "  FileVault already active; skipping enable."
elif [[ -n "${DOTFILES_SUDO_PASSWORD:-}" ]]; then
  # Use SUDO_ASKPASS so the sudo password channel doesn't collide with
  # fdesetup's plist on stdin (sudo_pw's `printf | sudo -S` would steal stdin
  # and starve fdesetup -> "Incoming data needs to be in a plist format").
  ASKPASS_SCRIPT=$(mktemp)
  cat >"$ASKPASS_SCRIPT" <<'ASKPASS_EOF'
#!/bin/sh
printf '%s\n' "$DOTFILES_SUDO_PASSWORD"
ASKPASS_EOF
  chmod 700 "$ASKPASS_SCRIPT"
  /usr/bin/python3 -c '
import os, plistlib, sys
sys.stdout.buffer.write(plistlib.dumps({
    "Username": os.environ["USER"],
    "Password": os.environ["DOTFILES_SUDO_PASSWORD"],
}, fmt=plistlib.FMT_XML))
' | SUDO_ASKPASS="$ASKPASS_SCRIPT" sudo -A fdesetup enable -inputplist
  rm -f "$ASKPASS_SCRIPT"
else
  sudo fdesetup enable
fi

echo "Done."

if [[ ${#SKIPPED[@]} -gt 0 ]]; then
  echo ""
  echo "Skipped writes (the OS rejected these — apply manually if needed):"
  for cmd in "${SKIPPED[@]}"; do
    printf '  - %s\n' "$cmd"
  done
fi

echo "Note: Trackpad changes may require log out/in to fully apply."
