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

source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

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
      err "unknown option: $1"
      exit 1
      ;;
  esac
  shift
done

need_cmd() { command -v "$1" >/dev/null 2>&1 || { err "missing command: $1"; exit 1; }; }
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

# Detect a guest VM (mirrors the Brewfile check) so host-only steps such as
# FileVault can be skipped on virtual machines.
is_vm() {
  [[ "$(/usr/sbin/sysctl -n kern.hv_vmm_present 2>/dev/null)" == "1" ]] && return 0
  /usr/sbin/sysctl -n hw.model 2>/dev/null | grep -qiE 'VirtualMac|VMware|Parallels|QEMU'
}

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
  warn "skipped (OS rejected): $*"
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

# Single cleanup hook: stop the sudo keepalive and remove the FileVault askpass
# helper, even if the run is interrupted. One EXIT trap so neither clobbers the
# other (bash keeps only the last trap registered per signal).
SUDO_KEEPALIVE_PID=""
ASKPASS_SCRIPT=""
cleanup() {
  if [[ -n "$SUDO_KEEPALIVE_PID" ]]; then
    kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
  fi
  if [[ -n "$ASKPASS_SCRIPT" ]]; then
    rm -f "$ASKPASS_SCRIPT"
  fi
}
trap cleanup EXIT

# Ask for admin once up front (used by Firewall and FileVault).
# Skip when invoked from opinionated-flow.sh, which already captured the
# password into DOTFILES_SUDO_PASSWORD; sudo_pw feeds it on every call.
if [[ "$DRY_RUN" -eq 0 && "${EUID:-$(id -u)}" -ne 0 && -z "${DOTFILES_SUDO_WARMED:-}" ]]; then
  repair_sudo_if_broken || exit 1
  sudo -v
  ( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) &
  SUDO_KEEPALIVE_PID=$!
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

echo "Keyboard: Press fn key to change input source"
defaults_write com.apple.HIToolbox AppleFnUsageType -int 1

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
  warn "could not set StartupMute NVRAM flag"
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
# System Events wallpaper scripting broke on Tahoe (26.x) after the wallpaper
# config moved under WallpaperAgent. NSWorkspace via the JS-ObjC bridge still
# works (same API desktoppr uses) and needs no Apple-events TCC grant.
set_wallpaper() {
  osascript -l JavaScript -e '
    ObjC.import("AppKit");
    function run(argv) {
      const url = $.NSURL.fileURLWithPath(argv[0]);
      const ws = $.NSWorkspace.sharedWorkspace;
      const screens = $.NSScreen.screens;
      for (let i = 0; i < screens.count; i++) {
        if (!ws.setDesktopImageURLForScreenOptionsError(url, screens.objectAtIndex(i), $.NSDictionary.dictionary, null)) {
          throw new Error("setDesktopImageURL failed for screen " + i);
        }
      }
    }' "$1"
}
if [[ -f "$BLACK_PNG" ]]; then
  optional set_wallpaper "$BLACK_PNG"
else
  warn "$BLACK_PNG not found; left desktop background unchanged"
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

echo "Menu Bar: Reduce item spacing"
defaults_current_host_write -globalDomain NSStatusItemSpacing -int 2
defaults_current_host_write -globalDomain NSStatusItemSelectionPadding -int 2

###############################################################################
# Terminal.app
###############################################################################

echo "Terminal: Set font size to 13 (default and startup profiles)"
optional osascript -e 'tell application "Terminal" to set font size of default settings to 13'
optional osascript -e 'tell application "Terminal" to set font size of startup settings to 13'

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
if is_vm; then
  echo "  Running inside a VM; skipping FileVault."
elif [[ "$DRY_RUN" -eq 1 ]]; then
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

# sudo_local is Apple's supported drop-in and survives OS updates; editing
# /etc/pam.d/sudo directly does not. Last step on purpose: from here on sudo may
# want a fingerprint, which the scripted sudo calls above cannot answer.
echo "Security: Enable Touch ID for sudo"

# openpam aborts the entire policy when a module cannot be dlopen'd - `optional`
# does not soften that - so one dangling path here breaks every sudo on the box
# with "unable to initialize PAM", including the sudo needed to undo it. Only
# ever name a module that exists on disk at write time. Prefix varies by chip
# (/opt/homebrew on Apple Silicon, /usr/local on Intel).
pam_reattach_so() {
  local prefix
  for prefix in "$(brew --prefix 2>/dev/null)" /opt/homebrew /usr/local; do
    if [[ -n "$prefix" && -f "$prefix/lib/pam/pam_reattach.so" ]]; then
      printf '%s\n' "$prefix/lib/pam/pam_reattach.so"
      return 0
    fi
  done
  return 1
}

# pam_reattach must come first or pam_tid fails inside tmux/screen, which are
# not attached to the GUI session.
sudo_local_body() {
  echo "# sudo_local: local config file which survives system update and is included for sudo"
  [[ -n "$PAM_REATTACH" ]] && printf 'auth       optional       %s ignore_ssh\n' "$PAM_REATTACH"
  echo "auth       sufficient     pam_tid.so"
}

# only the two lines this script writes, so hand edits are never clobbered
sudo_local_is_ours() {
  ! grep -qvE '^#|^[[:space:]]*$|^auth[[:space:]]+optional[[:space:]]+\S*pam_reattach\.so ignore_ssh$|^auth[[:space:]]+sufficient[[:space:]]+pam_tid\.so$' /etc/pam.d/sudo_local
}

warn_dangling_pam_modules() {
  local module
  while read -r module; do
    [[ -f "$module" ]] || warn "/etc/pam.d/sudo_local names missing $module; every sudo will fail until that file exists or the line goes"
  done < <(awk '/^auth/ && $3 ~ /^\// { print $3 }' /etc/pam.d/sudo_local)
}

PAM_REATTACH="$(pam_reattach_so || true)"
PAM_WRITE=1

if is_vm; then
  # no Secure Enclave passthrough in any macOS guest, so pam_tid can never
  # succeed; writing the file would only log a dlopen error on every sudo
  echo "  Running inside a VM; skipping Touch ID for sudo."
elif [[ ! -f /etc/pam.d/sudo_local.template ]]; then
  warn "no /etc/pam.d/sudo_local.template on this macOS; skipping Touch ID for sudo"
elif [[ "$DRY_RUN" -eq 1 ]]; then
  printf '  [dry-run] %s\n' "write /etc/pam.d/sudo_local (pam_tid${PAM_REATTACH:+ + pam_reattach})"
else
  # Brewfile.base carries pam-reattach, but `brew bundle` only runs after this
  # script, and by then a stale reference would already have killed sudo.
  if [[ -z "$PAM_REATTACH" ]] && command -v brew >/dev/null 2>&1; then
    echo "  Installing pam-reattach first (a missing module here would break sudo)."
    HOMEBREW_NO_AUTO_UPDATE=1 brew install pam-reattach >/dev/null \
      || warn "could not install pam-reattach"
    PAM_REATTACH="$(pam_reattach_so || true)"
  fi
  [[ -n "$PAM_REATTACH" ]] || warn "pam_reattach.so not found; writing pam_tid only, so Touch ID for sudo will not work inside tmux"

  if [[ -f /etc/pam.d/sudo_local ]]; then
    if diff -q <(sudo_local_body) /etc/pam.d/sudo_local >/dev/null 2>&1; then
      echo "  /etc/pam.d/sudo_local already configured."
      PAM_WRITE=0
    elif ! sudo_local_is_ours; then
      echo "  /etc/pam.d/sudo_local has local edits; leaving it alone."
      warn_dangling_pam_modules
      PAM_WRITE=0
    fi
  fi

  if [[ "$PAM_WRITE" -eq 1 ]]; then
    # piping into `sudo tee` would collide with sudo_pw's password-on-stdin,
    # hence mktemp + install
    PAM_TMP="$(mktemp)"
    sudo_local_body >"$PAM_TMP"
    if sudo_pw install -m 0444 -o root -g wheel "$PAM_TMP" /etc/pam.d/sudo_local; then
      # belt and braces: never leave the run with a sudo it cannot use
      if sudo_broken_by_pam; then
        err "the new /etc/pam.d/sudo_local broke sudo; removing it"
        if remove_sudo_local; then
          warn "Touch ID for sudo left unconfigured"
        else
          rm -f "$PAM_TMP"
          exit 1
        fi
      fi
    else
      warn "could not write /etc/pam.d/sudo_local"
    fi
    rm -f "$PAM_TMP"
  fi
fi

echo "Done."

if [[ ${#SKIPPED[@]} -gt 0 ]]; then
  echo ""
  warn "skipped writes (the OS rejected these; apply manually if needed):"
  for cmd in "${SKIPPED[@]}"; do
    warn "  - $cmd"
  done
fi

echo "Note: Trackpad changes may require log out/in to fully apply."
