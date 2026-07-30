#!/usr/bin/env bash
set -euo pipefail

# Enables Touch ID for sudo by writing /etc/pam.d/sudo_local, Apple's supported
# drop-in (it survives OS updates; editing /etc/pam.d/sudo directly does not).
#
# Its own script because it must run after every scripted sudo of a setup run:
# once pam_tid is in the policy, sudo asks for a fingerprint, which a piped
# password cannot answer. opinionated-flow.sh therefore defers it to the very
# end (DOTFILES_DEFER_TOUCHID=1) instead of letting macos-bootstrap.sh do it
# mid-run, and kills its sudo keepalive first so nothing re-authenticates after.
#
# Pass --dry-run (-n) to print what would be written without touching anything.

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
  # Brewfile.base carries pam-reattach, but this can run before that bundle (or
  # after it failed), and a stale reference would kill sudo.
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
