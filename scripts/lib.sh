#!/usr/bin/env bash

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

if [[ -t 1 ]]; then
  _SETUP_BOLD=$'\033[1m'
  _SETUP_CYAN=$'\033[36m'
  _SETUP_OUT_RESET=$'\033[0m'
else
  _SETUP_BOLD=""
  _SETUP_CYAN=""
  _SETUP_OUT_RESET=""
fi

section() { echo "${_SETUP_BOLD}${_SETUP_CYAN}==> $*${_SETUP_OUT_RESET}"; }

_SETUP_TTY_STATE="$({ stty -g </dev/tty; } 2>/dev/null || true)"

restore_tty() {
  [[ -n "$_SETUP_TTY_STATE" ]] || return 0
  { stty "$_SETUP_TTY_STATE" </dev/tty; } 2>/dev/null || true
}

brewfile_taps() {
  sed -n \
    -e 's/^[[:space:]]*tap[[:space:]]*"\([^"]*\)".*/\1/p' \
    -e 's|^[[:space:]]*brew[[:space:]]*"\([^"/]*/[^"/]*\)/[^"]*".*|\1|p' \
    -e 's|^[[:space:]]*cask[[:space:]]*"\([^"/]*/[^"/]*\)/[^"]*".*|\1|p' \
    "$@" 2>/dev/null | sort -u
}

brew_trust_store() {
  if [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
    printf '%s\n' "$XDG_CONFIG_HOME/homebrew/trust.json"
  else
    printf '%s\n' "$HOME/.homebrew/trust.json"
  fi
}

brewfile_untrusted_taps() {
  local store tap
  store="$(brew_trust_store)"
  brewfile_taps "$@" | while IFS= read -r tap; do
    [[ -n "$tap" ]] || continue
    grep -qi "\"$tap" "$store" 2>/dev/null || printf '%s\n' "$tap"
  done
}

trust_brewfile_taps() {
  local tap
  command -v brew >/dev/null 2>&1 || return 0
  brew trust --help >/dev/null 2>&1 || return 0

  brewfile_taps "$@" | while IFS= read -r tap; do
    [[ -n "$tap" ]] || continue
    brew tap "$tap" >/dev/null 2>&1 || true
    brew trust --tap "$tap" >/dev/null 2>&1 || true
  done
}

herdr_install_integration() {
  command -v herdr >/dev/null 2>&1 || return 0
  herdr integration install "$1" >/dev/null 2>&1 ||
    warn "herdr integration install $1 failed; agent session restore may not work."
}

is_vm() {
  [[ "$(/usr/sbin/sysctl -n kern.hv_vmm_present 2>/dev/null)" == "1" ]] && return 0
  /usr/sbin/sysctl -n hw.model 2>/dev/null | grep -qiE 'VirtualMac|VMware|Parallels|QEMU'
}

clt_required_major() {
  local os
  os="$(sw_vers -productVersion | cut -d. -f1)"
  if [[ "$os" -ge 26 ]]; then echo "$os"; else echo $((os + 1)); fi
}

clt_installed_major() {
  pkgutil --pkg-info=com.apple.pkg.CLTools_Executables 2>/dev/null |
    awk -F'[ .]' '/^version:/ { print $2; exit }'
}

ensure_clt_current() {
  local want have label sentinel listing attempt
  want="$(clt_required_major)"

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

sudo_broken_by_pam() {
  [[ -f /etc/pam.d/sudo_local ]] || return 1
  [[ "$(sudo -n true 2>&1 || true)" == *"initialize PAM"* ]]
}

install_missing_pam_reattach() {
  local prefix
  command -v brew >/dev/null 2>&1 || return 1
  prefix="$(brew --prefix 2>/dev/null)" || return 1
  [[ -n "$prefix" ]] || return 1
  grep -qF "$prefix/lib/pam/pam_reattach.so" /etc/pam.d/sudo_local || return 1
  echo "  Installing the pam-reattach module the policy references..."
  HOMEBREW_NO_AUTO_UPDATE=1 brew install pam-reattach >/dev/null 2>&1
}

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
