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

# openpam fails the whole sudo policy when a module named in /etc/pam.d/sudo_local
# cannot be dlopen'd, so every sudo dies with "unable to initialize PAM" - the one
# that would delete the file included. -n keeps the probe from ever prompting.
sudo_broken_by_pam() {
  [[ -f /etc/pam.d/sudo_local ]] || return 1
  [[ "$(sudo -n true 2>&1 || true)" == *"initialize PAM"* ]]
}

# Authorization Services is a separate auth path from sudo's PAM policy, so this
# still gets root on a machine whose sudo is dead. Needs a GUI session.
remove_sudo_local() {
  osascript -e 'do shell script "rm -f /etc/pam.d/sudo_local" with administrator privileges' >/dev/null 2>&1 && return 0
  err "could not remove /etc/pam.d/sudo_local; run this from a GUI Terminal, then rerun setup:"
  err "  osascript -e 'do shell script \"rm -f /etc/pam.d/sudo_local\" with administrator privileges'"
  return 1
}

# Call before the first sudo of a run: heals a machine left unable to sudo by an
# earlier bad sudo_local (e.g. one written before brew installed pam-reattach).
repair_sudo_if_broken() {
  sudo_broken_by_pam || return 0
  err "/etc/pam.d/sudo_local breaks sudo (\"unable to initialize PAM\"); removing it"
  remove_sudo_local || return 1
  echo "Removed /etc/pam.d/sudo_local; sudo works again."
}
