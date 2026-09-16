#!/usr/bin/env bash
# Shared logging and sudo-recovery helpers for the setup scripts. Source, do not
# execute.
#
# Unified prefixes make provisioning problems greppable across a whole `make`
# run, e.g. `make 2>&1 | grep SETUP_WARN` (or `grep SETUP_` for warnings and
# errors together). warn() = non-fatal, setup keeps going; err() = fatal,
# print right before exiting.
#
# Both colorize when stderr is a terminal so they stand out in a long run;
# color is dropped when redirected/piped so log files stay clean and still
# grep by prefix.

if [[ -t 2 ]]; then
  _SETUP_YELLOW=$'\033[33m'
  _SETUP_RED=$'\033[31m'
  _SETUP_RESET=$'\033[0m'
else
  _SETUP_YELLOW=""
  _SETUP_RED=""
  _SETUP_RESET=""
fi

warn() { echo "${_SETUP_YELLOW}SETUP_WARN: $*${_SETUP_RESET}" >&2; }
err() { echo "${_SETUP_RED}SETUP_ERROR: $*${_SETUP_RESET}" >&2; }

# Progress headers go to stdout, so they need their own tty test: a run piped
# to a file has a terminal on stderr surprisingly often, and vice versa.
if [[ -t 1 ]]; then
  _SETUP_BOLD=$'\033[1m'
  _SETUP_CYAN=$'\033[36m'
  _SETUP_OUT_RESET=$'\033[0m'
else
  _SETUP_BOLD=""
  _SETUP_CYAN=""
  _SETUP_OUT_RESET=""
fi

# Section header for a multi-step run. Bold so the eye can skip between stages
# in a long scrollback; the `==>` prefix stays greppable without color.
section() { echo "${_SETUP_BOLD}${_SETUP_CYAN}==> $*${_SETUP_OUT_RESET}"; }

# A password prompt that dies mid-read (a scripted sudo racing the keepalive, an
# interrupted run) leaves termios as it found it: newline stops implying carriage
# return, so every later line staircases and the prompt draws garbled until that
# window is closed. Snapshot before anything touches the tty, restore on exit.
# Empty when there is no controlling terminal, which makes restore a no-op.
# Braces around the redirect: with no tty it is bash, not stty, that reports
# "/dev/tty: Device not configured", so the group has to swallow stderr.
_SETUP_TTY_STATE="$({ stty -g </dev/tty; } 2>/dev/null || true)"

restore_tty() {
  [[ -n "$_SETUP_TTY_STATE" ]] || return 0
  { stty "$_SETUP_TTY_STATE" </dev/tty; } 2>/dev/null || true
}

# Homebrew will not load a non-official tap's formulae or casks until they are
# trusted, and trust.json is machine-local, so every machine needs its own
# grant. Untrusted does not merely fail to install: `brew bundle check` reports
# an installed tap formula as "needs to be installed or updated", so a bundle
# runs on every single pass and then dies on the tap.
#
# The taps are read out of the Brewfiles rather than listed here, because a list
# is what broke: the trust step lived only in opinionated-flow.sh, naming three
# taps by hand, and update.sh's `brew bundle` had no equivalent.
#
# One -e per form, never an alternation: BSD sed has no `\|` and takes it as a
# literal pipe rather than erroring, so the pattern silently never matches.
# `brew/Brewfile` itself is skipped by the callers - it only instance_evals the
# leaf files, which is where every tap entry actually lives.
brewfile_taps() {  # brewfile_taps <brewfile...>
  sed -n \
    -e 's/^[[:space:]]*tap[[:space:]]*"\([^"]*\)".*/\1/p' \
    -e 's|^[[:space:]]*brew[[:space:]]*"\([^"/]*/[^"/]*\)/[^"]*".*|\1|p' \
    -e 's|^[[:space:]]*cask[[:space:]]*"\([^"/]*/[^"/]*\)/[^"]*".*|\1|p' \
    "$@" 2>/dev/null | sort -u
}

# ~/.homebrew/trust.json unless XDG_CONFIG_HOME is set (see `brew trust --help`).
brew_trust_store() {
  if [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
    printf '%s\n' "$XDG_CONFIG_HOME/homebrew/trust.json"
  else
    printf '%s\n' "$HOME/.homebrew/trust.json"
  fi
}

# Read-only counterpart, for a dry run that must not write. Trust is recorded
# either per tap or per entry ("genkio/tap" vs "genkio/tap/herdlet"), so a
# prefix match answers both, case-insensitively - brew downcases what it stores.
brewfile_untrusted_taps() {  # brewfile_untrusted_taps <brewfile...>
  local store tap
  store="$(brew_trust_store)"
  brewfile_taps "$@" | while IFS= read -r tap; do
    [[ -n "$tap" ]] || continue
    grep -qi "\"$tap" "$store" 2>/dev/null || printf '%s\n' "$tap"
  done
}

# Tap-level, not per-entry: a tap grant covers whatever those Brewfiles gain
# later, which is the point of deriving the list from them.
trust_brewfile_taps() {  # trust_brewfile_taps <brewfile...>
  local tap
  command -v brew >/dev/null 2>&1 || return 0
  # Older Homebrew has no `trust` at all, and needs none.
  brew trust --help >/dev/null 2>&1 || return 0

  brewfile_taps "$@" | while IFS= read -r tap; do
    [[ -n "$tap" ]] || continue
    brew tap "$tap" >/dev/null 2>&1 || true
    brew trust --tap "$tap" >/dev/null 2>&1 || true
  done
}

# Detect a guest VM (mirrors the Brewfile check) so host-only steps such as
# FileVault and Touch ID can be skipped on virtual machines.
is_vm() {
  [[ "$(/usr/sbin/sysctl -n kern.hv_vmm_present 2>/dev/null)" == "1" ]] && return 0
  /usr/sbin/sysctl -n hw.model 2>/dev/null | grep -qiE 'VirtualMac|VMware|Parallels|QEMU'
}

# Homebrew refuses to install ANY formula, bottled ones included, when the
# Command Line Tools predate the running macOS: "Your Command Line Tools are
# too outdated". A macOS major upgrade leaves the old CLT in place and
# `xcode-select -p` still answers, so a presence check sails straight past it -
# that is what turned a whole `make` run into 12 failed formulae after a VM went
# from macOS 26 to 27 with CLT 16.4 still on disk.
#
# Apple aligned Xcode and CLT versions with macOS at 26 (Xcode 26 -> macOS 26)
# and ran one ahead before that (Xcode 16 -> macOS 15). Same table Homebrew's
# CLT.minimum_version uses.
clt_required_major() {
  local os
  os="$(sw_vers -productVersion | cut -d. -f1)"
  if [[ "$os" -ge 26 ]]; then echo "$os"; else echo $((os + 1)); fi
}

clt_installed_major() {
  pkgutil --pkg-info=com.apple.pkg.CLTools_Executables 2>/dev/null |
    awk -F'[ .]' '/^version:/ { print $2; exit }'
}

# `xcode-select --install` opens a modal dialog that nothing can answer over
# ssh, so drive softwareupdate instead. The sentinel file in /tmp is what makes
# softwareupdate list the CLT package at all - without it the label is hidden.
ensure_clt_current() {
  local want have label sentinel listing attempt
  want="$(clt_required_major)"

  # A full Xcode selected as the developer dir brings its own toolchain.
  [[ "$(xcode-select -p 2>/dev/null)" == *Xcode.app* ]] && return 0

  have="$(clt_installed_major)"
  if [[ -n "$have" && "$have" -ge "$want" ]]; then
    return 0
  fi

  if [[ -z "$have" ]]; then
    echo "Command Line Tools: not installed; installing (~500MB)..."
  else
    echo "Command Line Tools: $have is too old for macOS $(sw_vers -productVersion), need $want; updating (~500MB)..."
  fi

  sentinel=/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  : >"$sentinel" 2>/dev/null || true

  # Listing means reaching Apple's catalog, and on a machine still being set up
  # that fetch is the flakiest thing in the run: it fails by returning success
  # with an empty list, not by erroring, so one miss is not evidence the package
  # is unavailable. Retry before believing it, and keep the output around - the
  # first version of this threw it away and reported only "offered no package",
  # which said nothing about why.
  label=""
  for attempt in 1 2 3; do
    listing="$(softwareupdate -l 2>&1)"
    label="$(printf '%s\n' "$listing" |
      awk -F'Label: ' '/Label: Command Line Tools/ { print $2 }' |
      sort -V | tail -1)"
    if [[ -n "$label" ]]; then
      break
    fi
    if [[ "$attempt" -lt 3 ]]; then
      echo "  No Command Line Tools package offered yet; retrying in 15s..."
      sleep 15
    fi
  done

  if [[ -n "$label" ]]; then
    echo "  Installing: $label"
    sudo_pw softwareupdate -i "$label" --verbose || true
  else
    warn "softwareupdate offered no Command Line Tools package after 3 tries."
    warn "its last output was:"
    printf '%s\n' "$listing" | sed 's/^/    /' >&2
  fi
  rm -f "$sentinel"

  have="$(clt_installed_major)"
  if [[ -n "$have" && "$have" -ge "$want" ]]; then
    echo "  Command Line Tools now at $have."
    return 0
  fi

  err "Command Line Tools are ${have:-absent}, but macOS $(sw_vers -productVersion) needs $want."
  err "Homebrew refuses to install anything until this is fixed, so stopping here."
  err "This is usually a catalog fetch that did not land; 'make core' again is"
  err "the first thing to try. Failing that, install them by hand:"
  err "  sudo rm -rf /Library/Developer/CommandLineTools && xcode-select --install"
  return 1
}

# Feeds the captured password to sudo via stdin. Needed because Homebrew's
# brew.sh runs `sudo --reset-timestamp` on every invocation
# (Library/Homebrew/brew.sh:~1136), so the cache is dead right after any `brew`
# call. Falls back to plain sudo when no password is set (standalone runs).
#
# Restores the tty afterwards, keeping the exit status: a sudo underneath (brew
# starts its own for service ownership) can prompt on the terminal and leave
# termios raw when the keepalive refreshes the timestamp under it. Waiting for
# the EXIT trap is too late - every line printed in between staircases.
sudo_pw() {
  local rc=0
  if [[ -n "${DOTFILES_SUDO_PASSWORD:-}" ]]; then
    printf '%s\n' "$DOTFILES_SUDO_PASSWORD" | sudo -S "$@" || rc=$?
  else
    sudo "$@" || rc=$?
  fi
  restore_tty
  return "$rc"
}

# openpam fails the whole sudo policy when a module named in /etc/pam.d/sudo_local
# cannot be dlopen'd, so every sudo dies with "unable to initialize PAM" - the one
# that would delete the file included. -n keeps the probe from ever prompting.
sudo_broken_by_pam() {
  [[ -f /etc/pam.d/sudo_local ]] || return 1
  [[ "$(sudo -n true 2>&1 || true)" == *"initialize PAM"* ]]
}

# The usual cause is a pam_reattach line written before brew installed the
# module. Installing it makes the policy valid again and needs no root at all,
# so try that before reaching for admin rights.
install_missing_pam_reattach() {
  local prefix
  command -v brew >/dev/null 2>&1 || return 1
  prefix="$(brew --prefix 2>/dev/null)" || return 1
  [[ -n "$prefix" ]] || return 1
  grep -qF "$prefix/lib/pam/pam_reattach.so" /etc/pam.d/sudo_local || return 1
  echo "  Installing the pam-reattach module the policy references..."
  HOMEBREW_NO_AUTO_UPDATE=1 brew install pam-reattach >/dev/null 2>&1
}

# Authorization Services is a separate auth path from sudo's PAM policy, so it
# still gets root on a machine whose sudo is dead. Passing credentials skips the
# SecurityAgent dialog, which is unavailable over ssh and does not always appear
# even locally; env vars keep the password off the ps line.
remove_sudo_local() {
  local script="do shell script \"rm -f /etc/pam.d/sudo_local\"" out

  if [[ -n "${DOTFILES_SUDO_PASSWORD:-}" ]]; then
    out="$(osascript -e "$script user name \"$(id -un)\" password (system attribute \"DOTFILES_SUDO_PASSWORD\") with administrator privileges" 2>&1)" && return 0
    warn "removal with the captured password failed: $out"
  fi

  out="$(osascript -e "$script with administrator privileges" 2>&1)" && return 0
  err "could not remove /etc/pam.d/sudo_local: $out"
  err "remove it by hand, then rerun setup:"
  err "  osascript -e 'do shell script \"rm -f /etc/pam.d/sudo_local\" with administrator privileges'"
  err "or boot into Recovery (Cmd-R) and: rm -f /Volumes/Macintosh\\ HD/private/etc/pam.d/sudo_local"
  return 1
}

# Call before the first sudo of a run: heals a machine left unable to sudo by an
# earlier bad sudo_local (e.g. one written before brew installed pam-reattach).
repair_sudo_if_broken() {
  sudo_broken_by_pam || return 0
  err "/etc/pam.d/sudo_local breaks sudo (\"unable to initialize PAM\"); repairing"

  if install_missing_pam_reattach && ! sudo_broken_by_pam; then
    echo "Installed the pam_reattach module it referenced; sudo works again."
    return 0
  fi

  remove_sudo_local || return 1
  echo "Removed /etc/pam.d/sudo_local; sudo works again."
}
