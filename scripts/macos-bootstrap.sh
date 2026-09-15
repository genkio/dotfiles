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
COMPUTER_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run|-n)
      DRY_RUN=1
      ;;
    --name)
      [[ -n "${2:-}" ]] || { err "--name needs a value"; exit 1; }
      COMPUTER_NAME="$2"
      shift
      ;;
    -h|--help)
      echo "Usage: $(basename "$0") [--dry-run|-n] [--name NAME]"
      echo "  --dry-run, -n  Print what would be written without making changes."
      echo "  --name NAME    Rename the machine (default: leave it alone)."
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
  warn "skipped (OS rejected): $*"
  return 0
}

defaults_write() {
  optional defaults write "$@"
}

defaults_current_host_write() {
  optional defaults -currentHost write "$@"
}

# Single cleanup hook: stop the sudo keepalive, remove the FileVault askpass
# helper, and put the terminal back as we found it, even if the run is
# interrupted. One EXIT trap so none clobbers the others (bash keeps only the
# last trap registered per signal).
SUDO_KEEPALIVE_PID=""
ASKPASS_SCRIPT=""
cleanup() {
  if [[ -n "$SUDO_KEEPALIVE_PID" ]]; then
    kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
  fi
  if [[ -n "$ASKPASS_SCRIPT" ]]; then
    rm -f "$ASKPASS_SCRIPT"
  fi
  restore_tty
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
# Software Update
###############################################################################

# First real step of the run, ahead of the CLT install below and every other
# fetch, because it is the one that decides how long the rest takes.
#
# A just-installed macOS starts pulling every pending update in the background.
# Measured on a fresh 15.7 image: Safari + a 2GB point release + a 10GB Tahoe
# upgrade, ~3GB in before provisioning had finished cloning Homebrew. It eats
# the whole uplink, so the `brew bundle` that follows looks hung for hours.
# Only scheduling is disabled; XProtect/MRT data updates (ConfigDataInstall)
# are a separate key and stay on. Re-enable in System Settings > General >
# Software Update, or run `softwareupdate -l -i -a` by hand.
echo "Software Update: Disable automatic check, download and install"
optional sudo_pw defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled -bool false
optional sudo_pw defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool false
optional sudo_pw defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool false
optional sudo_pw softwareupdate --schedule off

# Those keys only govern the NEXT check. A download already in flight keeps
# going: the bytes belong to nsurlsessiond, whose background sessions outlive
# the client that queued them, softwareupdated is an on-demand job that can exit
# without stopping it, and `softwareupdate` has no cancel verb at all. So the
# best available here is to notice and say so - an unexplained 20-minute stall
# in a later `brew bundle` is far worse than four seconds of measuring.
# Growth, not size: staged bytes from a past update sit there for weeks.
su_staged_kb() {
  { sudo_pw du -sk /Library/Updates /System/Volumes/Update/MobileAsset 2>/dev/null || true; } |
    awk '{ total += $1 } END { print total + 0 }'
}
SU_DOWNLOADING=0
if [[ "$DRY_RUN" -eq 1 ]]; then
  printf '  [dry-run] %s\n' 'sample /Library/Updates for a download already in flight'
else
  SU_BEFORE="$(su_staged_kb)"
  sleep 4
  SU_GROWTH=$(($(su_staged_kb) - SU_BEFORE))
  # 1MB in 4s: well above filesystem noise, well below any real update download.
  if [[ "$SU_GROWTH" -gt 1024 ]]; then
    SU_DOWNLOADING=1
    warn "a macOS update is downloading RIGHT NOW (+$((SU_GROWTH / 1024))MB in 4s)."
    warn "the settings above stop the next one; they cannot cancel this one."
    warn "it will compete with everything below for bandwidth, starting with the"
    warn "Command Line Tools. Rebooting now is usually faster than pushing on."
    # Timed, and skipped without a terminal: this phase is meant to be runnable
    # unattended and over ssh, so a prompt that can block forever is a worse bug
    # than the download it is warning about.
    if [[ -t 0 ]]; then
      SU_REPLY=""
      read -r -t 30 -p "  Continue anyway? [Y/n] (continues on its own in 30s) " SU_REPLY || true
      echo ""
      if [[ "$SU_REPLY" == [nN]* ]]; then
        err "stopped. Reboot, then run 'make macos' again."
        exit 1
      fi
    fi
  fi
fi

# The Dock rewrite and the wallpaper-store walk below are both /usr/bin/python3,
# a CLT shim that pops a GUI installer dialog and blocks forever over ssh rather
# than failing. Cloning this repo needs /usr/bin/git, the same kind of shim, so
# in practice the tools are always here; assert rather than install, and turn
# the one way it can go wrong into an error instead of a hang.
if ! xcode-select -p >/dev/null 2>&1; then
  err "Xcode Command Line Tools are required (for /usr/bin/python3)."
  err "Install them with 'xcode-select --install', then rerun."
  exit 1
fi

###############################################################################
# Computer Name
###############################################################################

# Opt-in: no --name means leave whatever the setup assistant chose. macOS keeps
# four names and only ComputerName is the one in System Settings, so setting
# that alone leaves the shell prompt and the .local address on "Jis-MacBook-Pro".
# LocalHostName and HostName take letters, digits and hyphens only - anything
# else is rejected outright, so derive them instead of passing the name through.
if [[ -n "$COMPUTER_NAME" ]]; then
  SHORT_NAME="$(printf '%s' "$COMPUTER_NAME" | tr ' ' '-' | tr -cd 'A-Za-z0-9-')"
  if [[ -z "$SHORT_NAME" ]]; then
    err "--name '$COMPUTER_NAME' has no letters, digits or hyphens to build a hostname from."
    exit 1
  fi
  echo "Computer Name: $COMPUTER_NAME (ssh/mDNS: ${SHORT_NAME}.local)"
  optional sudo_pw scutil --set ComputerName "$COMPUTER_NAME"
  optional sudo_pw scutil --set LocalHostName "$SHORT_NAME"
  optional sudo_pw scutil --set HostName "$SHORT_NAME"
  # The SMB name is the fourth, capped at 15 chars and conventionally uppercase.
  optional sudo_pw defaults write \
    /Library/Preferences/SystemConfiguration/com.apple.smb.server \
    NetBIOSName -string "$(printf '%.15s' "$SHORT_NAME" | tr 'a-z' 'A-Z')"
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

# idleTime and askForPassword still live in the per-host (ByHost) screensaver
# domain, but the module *selection* left it in macOS 14: WallpaperAgent owns
# that now and ignores moduleDict, while still accepting the write. That silent
# accept is why this looked like it worked for so long.
echo "Screen Saver: Start after 5 minutes idle"
defaults_current_host_write com.apple.screensaver idleTime -int 300

# WallpaperAgent stores the choice as a binary plist repeated at every "Idle"
# node of its index: all-displays, system default, and one per display and per
# space. Those keys are UUIDs of *this* machine's displays and spaces, so walk
# the tree instead of seeding a captured file. Kill the agent first, or it
# writes its in-memory copy back over ours when it exits.
#
# A fresh account has no Idle node at all: desktop and screen saver start
# "linked" (one Linked node, Type "linked"), and the split into Desktop + Idle
# only happens when something picks a saver. So unlink first, keeping the
# wallpaper as Desktop, or this silently patches nothing - which is exactly how
# it failed on a new VM.
echo "Screen Saver: Use Fliqlo"
set_screen_saver() {
  killall WallpaperAgent 2>/dev/null || true
  # The store is written lazily, so on a new account the file does not exist
  # until the agent respawns and creates it. Measured at ~1s.
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [[ -e "$HOME/Library/Application Support/com.apple.wallpaper/Store/Index.plist" ]] && break
    sleep 1
  done
  /usr/bin/python3 - "$1" <<'PY'
import datetime, os, plistlib, sys
from urllib.parse import quote

saver = sys.argv[1]
idx = os.path.expanduser(
    "~/Library/Application Support/com.apple.wallpaper/Store/Index.plist")
if not os.path.exists(idx):
    sys.exit("wallpaper store missing")

config = plistlib.dumps({"module": {"relative": "file://" + quote(saver)}},
                        fmt=plistlib.FMT_BINARY)
opts = plistlib.dumps(
    {"values": {"legacyScreenSaverGenerationCount": {"picker": {"_0": {"id": "2"}}}}},
    fmt=plistlib.FMT_BINARY)
choice = {"Configuration": config, "Files": [],
          "Provider": "com.apple.wallpaper.choice.screen-saver"}

d = plistlib.load(open(idx, "rb"))
n = 0

def set_idle(content):
    content["Choices"] = [choice]
    content["EncodedOptionValues"] = opts

def walk(node):
    global n
    if not isinstance(node, dict):
        return
    linked = node.get("Linked")
    if isinstance(linked, dict) and "Content" in linked:
        del node["Linked"]
        node["Type"] = "individual"
        node["Desktop"] = linked
        stamp = linked.get("LastSet", datetime.datetime.now())
        node["Idle"] = {"LastSet": stamp, "LastUse": stamp,
                        "Content": {"Choices": [], "Shuffle": "$null"}}
        set_idle(node["Idle"]["Content"])
        n += 1
        return
    for key, value in node.items():
        if key == "Idle" and isinstance(value, dict) and "Content" in value:
            set_idle(value["Content"])
            n += 1
        else:
            walk(value)

walk(d)
if not n:
    sys.exit("no screen-saver slots in wallpaper store")
plistlib.dump(d, open(idx, "wb"), fmt=plistlib.FMT_BINARY)
PY
  killall WallpaperAgent 2>/dev/null || true
}
FLIQLO="${HOME}/Library/Screen Savers/Fliqlo.saver"
# Installed from here rather than Brewfile.apps: the selection below needs the
# bundle on disk NOW, and the apps bundle runs after this script - so on a fresh
# machine the choice used to warn, skip, and only take on a second run.
# Non-fatal: a failed download costs the screen saver, not the bootstrap.
if [[ "$DRY_RUN" -eq 1 ]]; then
  bash "$(dirname -- "${BASH_SOURCE[0]}")/install-fliqlo.sh" --dry-run
else
  bash "$(dirname -- "${BASH_SOURCE[0]}")/install-fliqlo.sh" ||
    warn "Fliqlo install failed; rerun scripts/install-fliqlo.sh."
fi
optional set_screen_saver "$FLIQLO"

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

echo "Power: Limit battery charge to 80%"
# The Battery > Charge Limit toggle (Sequoia+, Apple silicon laptops) has no
# pmset/defaults equivalent: System Settings drives powerd through PowerUI's
# smart-charge XPC client, so drive the same client. Needs no root, and the
# policy powerd persists is the same `manualChargeLimit` the UI writes.
set_charge_limit() {
  osascript -l JavaScript -e '
    ObjC.import("Foundation");
    function run(argv) {
      $.NSBundle.bundleWithPath("/System/Library/PrivateFrameworks/PowerUI.framework").load;
      const cls = $.NSClassFromString("PowerUISmartChargeClient");
      if (!cls) { throw new Error("PowerUISmartChargeClient unavailable"); }
      const client = cls.alloc.initWithClientName("macos-bootstrap");
      if (!client.isMCLSupported) { throw new Error("charge limit unsupported on this Mac"); }
      const err = $();
      if (!client.setMCLLimitError(parseInt(argv[0], 10), err)) {
        throw new Error("setMCLLimit failed");
      }
    }' "$1"
}
if pmset -g batt 2>/dev/null | grep -q InternalBattery; then
  optional set_charge_limit 80
else
  echo "  No internal battery; skipping."
fi

###############################################################################
# Desktop Background
###############################################################################

echo "Desktop: Set solid black background"
BLACK_PNG="/System/Library/Desktop Pictures/Solid Colors/Black.png"
# Two paths, gated on the OS major, because the thing that changed is an OS bug
# and each path is verified only on the releases it runs on. Do not "simplify"
# this into one: both single-path versions were tried and each breaks a release.
#
# <= 26: NSWorkspace.setDesktopImageURL. System Events wallpaper scripting broke
# on Tahoe 26.x when the config moved under WallpaperAgent, but this API still
# covers every node and needs no Apple-events TCC grant.
#
# >= 27: the same call reaches SystemDefault, Displays/<uuid> and a Spaces entry
# keyed by the EMPTY STRING, but leaves the node for the space actually on
# screen (Spaces/<space-uuid>/...) on its old image - and still returns true, so
# the run reports success and the desktop does not change. Nor can it be used as
# a first step feeding a repair pass: whether the agent has persisted the call
# to Index.plist by the time we read it is pure timing, measured anywhere
# between 100ms and never, so a poll either races or copies the PREVIOUS image
# over every node. So on 27 drive the store directly, exactly as the screen
# saver above does.
set_wallpaper_api() {
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

set_wallpaper_store() {
  killall WallpaperAgent 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [[ -e "$HOME/Library/Application Support/com.apple.wallpaper/Store/Index.plist" ]] && break
    sleep 1
  done
  local rc=0
  /usr/bin/python3 - "$1" <<'PY' || rc=$?
import os, plistlib, sys
from urllib.parse import quote

image = sys.argv[1]
idx = os.path.expanduser(
    "~/Library/Application Support/com.apple.wallpaper/Store/Index.plist")
if not os.path.exists(idx):
    sys.exit("wallpaper store missing")

config = plistlib.dumps({"type": "imageFile",
                         "url": {"relative": "file://" + quote(image)}},
                        fmt=plistlib.FMT_BINARY)
choice = {"Configuration": config, "Files": [],
          "Provider": "com.apple.wallpaper.choice.image"}

d = plistlib.load(open(idx, "rb"))
n = 0


def walk(node):
    global n
    if not isinstance(node, dict):
        return
    for key, value in node.items():
        # Never descend into Idle: that is the screen saver, set separately.
        # A Linked node has no split yet, so its one Content is the desktop too.
        if key == "Idle":
            continue
        if key in ("Desktop", "Linked") and isinstance(value, dict) and "Content" in value:
            value["Content"]["Choices"] = [choice]
            n += 1
        else:
            walk(value)


walk(d)
if not n:
    sys.exit("no desktop slots in wallpaper store")
plistlib.dump(d, open(idx, "wb"), fmt=plistlib.FMT_BINARY)
PY
  killall WallpaperAgent 2>/dev/null || true
  return "$rc"
}

set_wallpaper() {
  if [[ "$MACOS_MAJOR" -ge 27 ]]; then
    set_wallpaper_store "$1"
  else
    set_wallpaper_api "$1"
  fi
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
# Remote Access
###############################################################################

# Turned on early in provisioning so the rest of the setup can be driven over
# ssh from another machine instead of the console.
echo "Remote Access: Enable Remote Login (SSH)"
remote_login_on() { [[ "$(sudo_pw systemsetup -getremotelogin 2>/dev/null)" == *On* ]]; }
if [[ "$DRY_RUN" -eq 1 ]]; then
  printf '  [dry-run] %s\n' 'sudo systemsetup -setremotelogin on'
elif remote_login_on; then
  echo "  Already on."
else
  REMOTE_ERR="$(sudo_pw systemsetup -setremotelogin on 2>&1 || true)"
  if remote_login_on; then
    echo "  Enabled."
  else
    # macOS gates this toggle behind Full Disk Access for the CALLING app, and a
    # fresh Terminal has no such grant. launchctl reaches the same daemon
    # without it; bootstrap fails harmlessly when the job is already loaded.
    sudo_pw launchctl enable system/com.openssh.sshd >/dev/null 2>&1 || true
    sudo_pw launchctl bootstrap system /System/Library/LaunchDaemons/ssh.plist >/dev/null 2>&1 || true
    if remote_login_on; then
      echo "  Enabled via launchctl (systemsetup wanted Full Disk Access)."
    else
      warn "could not enable Remote Login: ${REMOTE_ERR:-unknown error}"
      warn "enable it by hand in System Settings > General > Sharing > Remote Login."
    fi
  fi
fi

###############################################################################
# System
###############################################################################

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
if is_vm; then
  echo "  Running inside a VM; skipping FileVault."
elif [[ "$DRY_RUN" -eq 1 ]]; then
  echo "  [dry-run] would check fdesetup isactive and run 'sudo fdesetup enable' if not active"
elif sudo_pw fdesetup isactive >/dev/null 2>&1; then
  echo "  FileVault already active; skipping enable."
elif [[ -n "${DOTFILES_SUDO_PASSWORD:-}" ]]; then
  # fdesetup prints the personal recovery key on stdout, so on a terminal it ends
  # up in scrollback and in any tee'd setup log - permanently, and in the repo if
  # the log is saved there. Redirect it to a 0600 file created before the run so
  # the key never has a world-readable moment.
  FV_KEY_FILE="$HOME/filevault-recovery-key.txt"
  (umask 077; : >"$FV_KEY_FILE")
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
' | SUDO_ASKPASS="$ASKPASS_SCRIPT" sudo -A fdesetup enable -inputplist >"$FV_KEY_FILE"
  rm -f "$ASKPASS_SCRIPT"
  if grep -q "Recovery key" "$FV_KEY_FILE" 2>/dev/null; then
    echo "  Recovery key written to $FV_KEY_FILE (mode 600)."
    echo "  Move it into your password manager, then delete the file."
  else
    warn "FileVault enable printed no recovery key; inspect $FV_KEY_FILE."
  fi
else
  warn "FileVault is about to print the recovery key on screen: store it in your"
  warn "password manager, and keep it out of any saved transcript of this run."
  sudo fdesetup enable
fi

# Last, and skipped entirely when the caller says it will run it later: pam_tid
# makes sudo ask for a fingerprint, which no scripted sudo can answer, so it has
# to come after the final sudo of the whole setup run - not just this script's.
if [[ -z "${DOTFILES_DEFER_TOUCHID:-}" ]]; then
  TOUCHID_SCRIPT="$(dirname -- "${BASH_SOURCE[0]}")/touchid-sudo.sh"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    bash "$TOUCHID_SCRIPT" --dry-run
  else
    bash "$TOUCHID_SCRIPT"
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

# Repeated from the Software Update section: that warning is ~300 lines up by
# now, and this is the one finding that changes what you do next.
if [[ "$SU_DOWNLOADING" -eq 1 ]]; then
  echo ""
  warn "a macOS update was still downloading when this phase started, and"
  warn "disabling automatic updates does not cancel it. Reboot before 'make"
  warn "core', or the download will starve every later phase of bandwidth."
fi

# Last line of the run, so it survives the scrollback: with Remote Login on,
# this is how you reach the machine to drive the rest of the setup remotely.
# The default route's interface rather than a hardcoded en0 - en0 is Wi-Fi on a
# laptop but not on a Mac on ethernet, or behind a USB adapter.
LOCAL_IFACE="$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')"
LOCAL_IP="$(ipconfig getifaddr "${LOCAL_IFACE:-en0}" 2>/dev/null || true)"
LOCAL_NAME="$(scutil --get LocalHostName 2>/dev/null || true)"
# The mDNS name first: it follows the machine, while a DHCP lease can move to a
# different host and then ssh refuses the whole connection over a known_hosts
# conflict. The IP stays as the fallback for anywhere mDNS does not reach
# (another subnet, a VPN).
if [[ -n "$LOCAL_NAME" ]]; then
  echo "SSH to this machine: ssh $(id -un)@${LOCAL_NAME}.local"
fi
if [[ -n "$LOCAL_IP" ]]; then
  echo "                 or: ssh $(id -un)@${LOCAL_IP}   (${LOCAL_IFACE:-en0}, DHCP)"
fi
if [[ -z "$LOCAL_NAME" && -z "$LOCAL_IP" ]]; then
  warn "could not determine this machine's local name or IP on ${LOCAL_IFACE:-en0}"
fi
echo "  If ssh answers REMOTE HOST IDENTIFICATION HAS CHANGED, that address used"
echo "  to belong to another machine. Clear it on the client you connect FROM,"
echo "  not here: ssh-keygen -R <the address above>"
