#!/usr/bin/env bash
set -euo pipefail

# Opinionated first-run bootstrap for this dotfiles repo.
#
# The script is intentionally a full machine setup path, not just a stow helper:
# clone or reuse the repo, install base Homebrew packages, stow the core package
# set, seed tmux/git/ssh defaults, and optionally install GUI apps, dev tooling,
# and macOS preference tweaks. Keep this aligned with AGENTS.md/CLAUDE.md before
# changing package names or setup order.

REPO_URL="${REPO_URL:-https://github.com/genkio/dotfiles.git}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
INCLUDE_APPS=0
INCLUDE_DEV=0
BOOTSTRAP_MACOS=0
BREW_BUNDLE_FAILURES=()

source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --include-all)
      INCLUDE_APPS=1
      INCLUDE_DEV=1
      ;;
    --include-apps)
      INCLUDE_APPS=1
      ;;
    --include-dev)
      INCLUDE_DEV=1
      ;;
    --bootstrap-macos)
      BOOTSTRAP_MACOS=1
      ;;
    -h|--help)
      echo "Usage: $(basename "$0") [--include-all] [--include-apps] [--include-dev] [--bootstrap-macos]"
      exit 0
      ;;
    *)
      err "unknown option: $1"
      exit 1
      ;;
  esac
  shift
done

# Single cleanup hook, registered before the first tty or sudo touch: bash keeps
# only the last EXIT trap, so everything the run has to undo goes here.
SUDO_KEEPALIVE_PID=""
cleanup() {
  if [[ -n "$SUDO_KEEPALIVE_PID" ]]; then
    kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
  fi
  unset DOTFILES_SUDO_PASSWORD DOTFILES_SUDO_WARMED
  restore_tty
}
trap cleanup EXIT

# Capture password once up front. Used for sudo (kept warm via -S in the
# keepalive so it survives even if the timestamp expires during long brew
# steps) and for FileVault's fdesetup -inputplist (avoids its separate
# Secure Token prompt). Cleared on exit. Exported so macos-bootstrap.sh
# inherits it; DOTFILES_SUDO_WARMED tells children to skip their own prompt.
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  if [[ -z "${DOTFILES_SUDO_PASSWORD:-}" ]]; then
    printf 'Password (used once for sudo and FileVault): '
    stty -echo
    IFS= read -r DOTFILES_SUDO_PASSWORD
    stty echo
    printf '\n'
  fi
  export DOTFILES_SUDO_PASSWORD
  export DOTFILES_SUDO_WARMED=1

  # after the password is captured: the repair can then authenticate without a
  # SecurityAgent dialog. Before the check below, which a broken PAM policy would
  # otherwise fail as "authentication failed".
  repair_sudo_if_broken || exit 1

  if ! printf '%s\n' "$DOTFILES_SUDO_PASSWORD" | sudo -S -v 2>/dev/null; then
    err "sudo authentication failed."
    unset DOTFILES_SUDO_PASSWORD DOTFILES_SUDO_WARMED
    exit 1
  fi

  ( while kill -0 "$$" 2>/dev/null; do
      printf '%s\n' "$DOTFILES_SUDO_PASSWORD" | sudo -S -v 2>/dev/null || true
      sleep 60
    done ) &
  SUDO_KEEPALIVE_PID=$!
fi

# Skip the slow `brew bundle` install attempt when every entry is already
# installed AND up-to-date. `brew bundle check` only dependency-resolves
# (no install). HOMEBREW_NO_AUTO_UPDATE=1 keeps the probe itself fast;
# the real install below can still auto-update when it actually runs.
brew_bundle_install() {
  local file="$1"
  if HOMEBREW_NO_AUTO_UPDATE=1 brew bundle check --file "$file" >/dev/null 2>&1; then
    echo "brew bundle: $file already satisfied, skipping"
    return 0
  fi
  # brew bundle keeps going past a failed formula/cask, installs everything
  # else, then exits non-zero with a summary. Swallow that non-zero so `set -e`
  # doesn't abort the whole provisioning run over one bad package (e.g.
  # sevenzip); record it and surface a summary at the end instead.
  if ! brew bundle --file "$file"; then
    warn "some entries in $file failed to install; continuing setup."
    BREW_BUNDLE_FAILURES+=("$file")
  fi
}

if [[ -d "$DOTFILES_DIR/.git" ]]; then
  if git -C "$DOTFILES_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Using existing repo at $DOTFILES_DIR"
  else
    err "$DOTFILES_DIR looks like a git repo, but it is incomplete or corrupt."
    err "Remove it and rerun the bootstrap."
    exit 1
  fi
else
  if [[ -e "$DOTFILES_DIR" ]]; then
    err "$DOTFILES_DIR exists but is not a git repo."
    exit 1
  fi
  echo "Cloning $REPO_URL to $DOTFILES_DIR"
  git clone "$REPO_URL" "$DOTFILES_DIR"
fi

cd "$DOTFILES_DIR"

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew not found. Installing..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Add brew to PATH for this session (Apple Silicon vs Intel)
  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -f /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
fi

if ! command -v stow >/dev/null 2>&1; then
  echo "GNU stow not found. Installing with Homebrew..."
  brew install stow
fi

# Run early so tap-to-click etc. apply during the long brew bundle below.
# Homebrew install above pulled in Xcode CLT -> /usr/bin/python3 (Dock mutation) works.
if [[ "$BOOTSTRAP_MACOS" -eq 1 ]]; then
  if [[ ! -f scripts/macos-bootstrap.sh ]]; then
    err "scripts/macos-bootstrap.sh not found."
    exit 1
  fi

  # Touch ID for sudo is the one setting that must wait for the end of the whole
  # run, not just this script: see the deferred call below.
  DOTFILES_DEFER_TOUCHID=1 bash scripts/macos-bootstrap.sh
fi

# carbonyl ships from third-party genkio/tap. Newer Homebrew refuses to load
# non-official tap formulae until trusted (HOMEBREW_REQUIRE_TAP_TRUST, slated to
# become default) -> `brew bundle` aborts without this. Guarded: older brew
# lacks `trust`, re-runs are no-ops.
brew tap genkio/tap >/dev/null 2>&1 || true
brew trust genkio/tap || true

brew_bundle_install brew/Brewfile.base
# sudo: run as root LaunchDaemon for always-on server (no user login required).
# Tradeoff: brew upgrade/uninstall of tailscale needs manual `sudo rm` of its paths.
# Non-fatal: if tailscale itself failed in the bundle above, don't abort the rest.
sudo_pw brew services start tailscale \
  || warn "could not start tailscale service; run 'sudo brew services start tailscale' later."
# After bootstrap, run separately (bundling exit-node into `up` can silently drop it):
#   sudo tailscale up --ssh --operator=$USER # prints login URL, auth in browser
#   sudo tailscale set --advertise-exit-node # then approve in admin console
# To USE a remote exit node from this mac: scripts/tailscale-exit.sh on|off|status
# (tailscaled on macOS never programs the v4 default route; the script adds it)
# echo "net.inet.ip.forwarding=1" | sudo tee -a /etc/sysctl.conf
# echo "net.inet6.ip6.forwarding=1" | sudo tee -a /etc/sysctl.conf
mkdir -p "$HOME/.config/mpv"
stow -t "$HOME" brew mpv nvim tmux vim yazi zsh

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
if [[ -e "$HOME/.ssh/config" && ! -L "$HOME/.ssh/config" ]]; then
  echo "Skipping ssh stow: ~/.ssh/config already exists and is not a symlink."
  echo "Move it aside and run 'cd $DOTFILES_DIR && stow ssh' when you're ready."
else
  stow -t "$HOME" ssh
fi

TPM_DIR="$HOME/.tmux/plugins/tpm"
if [[ -d "$TPM_DIR/.git" ]]; then
  echo "TPM already installed at $TPM_DIR"
elif [[ -e "$TPM_DIR" ]]; then
  echo "Skipping TPM install: $TPM_DIR exists and is not a git repo."
else
  mkdir -p "$(dirname "$TPM_DIR")"
  git clone https://github.com/tmux-plugins/tpm "$TPM_DIR"
fi
if [[ -x "$TPM_DIR/bin/install_plugins" ]]; then
  "$TPM_DIR/bin/install_plugins"
  echo "Installed tmux plugins from ~/.tmux.conf"
fi

if [[ -e "$HOME/.gitconfig" && ! -L "$HOME/.gitconfig" ]]; then
  echo "Skipping git stow: ~/.gitconfig already exists and is not a symlink."
  echo "Move it aside and run 'cd $DOTFILES_DIR && stow git' when you're ready."
else
  stow -t "$HOME" git
  if [[ ! -e "$HOME/.gitconfig.local" ]]; then
    cp "$DOTFILES_DIR/git/.gitconfig.local.example" "$HOME/.gitconfig.local"
    echo "Seeded ~/.gitconfig.local from $DOTFILES_DIR/git/.gitconfig.local.example"
    echo "Edit ~/.gitconfig.local for your private Git identity."
  fi
fi

if [[ "$INCLUDE_APPS" -eq 1 ]]; then
  brew_bundle_install brew/Brewfile.apps
  stow -t "$HOME" hammerspoon
  # Non-fatal: a failed Package Control download shouldn't abort provisioning.
  bash scripts/setup-sublime.sh \
    || warn "Sublime Package Control setup failed; run 'make sublime' later."
fi

if [[ "$INCLUDE_DEV" -eq 1 ]]; then
  bash scripts/setup-dev.sh
fi

# Deliberately last: pam_tid makes sudo ask for a fingerprint, which the piped
# password cannot answer, so nothing that sudos may follow. The keepalive is the
# main offender - it re-authenticates every 60s, and every `brew` call resets the
# timestamp, so it would pop a Touch ID prompt over and over.
if [[ "$BOOTSTRAP_MACOS" -eq 1 ]]; then
  if [[ -n "${SUDO_KEEPALIVE_PID:-}" ]]; then
    kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    SUDO_KEEPALIVE_PID=""
  fi
  # sudo_pw feeds the password on stdin, so the dead keepalive costs it nothing
  bash scripts/touchid-sudo.sh || warn "Touch ID for sudo not configured; rerun 'bash scripts/touchid-sudo.sh'"
fi

if [[ ${#BREW_BUNDLE_FAILURES[@]} -gt 0 ]]; then
  echo >&2
  warn "setup finished, but brew bundle reported failures for:"
  for f in "${BREW_BUNDLE_FAILURES[@]}"; do
    warn "  - $f"
  done
  warn "retry with 'brew bundle --file <file>', or install the missing package directly with 'brew install <name>'."
fi

# The two steps this script cannot do for you: one needs a private identity, the
# other a browser login. Printed last so they survive the scrollback, and only
# when still pending so a re-run stays quiet.
NEXT_STEPS=()
PLACEHOLDER_EMAIL="$(git config -f "$DOTFILES_DIR/git/.gitconfig.local.example" user.email 2>/dev/null || true)"
CURRENT_EMAIL="$(git config user.email 2>/dev/null || true)"
if [[ -z "$CURRENT_EMAIL" || "$CURRENT_EMAIL" == "$PLACEHOLDER_EMAIL" ]]; then
  NEXT_STEPS+=("make ssh   # SSH key + your real git identity in ~/.gitconfig.local")
fi
# `tailscale status` exits 0 even when logged out, so read the backend state.
if command -v tailscale >/dev/null 2>&1 &&
  ! tailscale status --json 2>/dev/null | grep -q '"BackendState": *"Running"'; then
  NEXT_STEPS+=("make tailscale   # tailnet login; prints a URL to authorize in the browser")
fi
# uv drops maestral in ~/.local/bin, which this script's PATH need not have:
# setup-dev.sh exports it for its own process only. `auth status` exits non-zero
# until an account is linked ("Configuration 'maestral' does not exist").
MAESTRAL_BIN="$(command -v maestral || true)"
[[ -n "$MAESTRAL_BIN" ]] || MAESTRAL_BIN="$HOME/.local/bin/maestral"
MAESTRAL_PENDING=""
if [[ -x "$MAESTRAL_BIN" ]] && ! "$MAESTRAL_BIN" auth status >/dev/null 2>&1; then
  NEXT_STEPS+=("box auth link   # Dropbox sign-in, then 'box start' and 'box autostart -Y'")
  MAESTRAL_PENDING=1
fi
if [[ ${#NEXT_STEPS[@]} -gt 0 ]]; then
  # Belt and braces: the keepalive can break the tty at any point in a long run,
  # not only inside a sudo_pw call, and this block is the output that has to stay
  # readable.
  restore_tty
  echo
  echo "Still to do by hand:"
  for step in "${NEXT_STEPS[@]}"; do
    echo "  $step"
  done
  # setup-dev.sh already installs maestral with both pins (see the comment
  # there). This stays for a maestral that arrived some other way, or one whose
  # pins a `uv tool upgrade` quietly dropped - the failure is identical either
  # way. The --python 3.13 half matters: rubicon-objc < 0.5.5 cannot run on
  # 3.14, which removed the event loop policy API it subclasses.
  if [[ -n "$MAESTRAL_PENDING" ]]; then
    echo
    echo '  If "box start" fails, check "maestral log show": on "ObjC Class NSEvent"'
    echo '  not found, the daemon got rubicon-objc >= 0.5.5. Reinstall it pinned:'
    echo "    uv tool install --force maestral --managed-python --python 3.13 \\"
    echo "      --with 'rubicon-objc<0.5.5'"
    echo '  If "box start" hangs printing nothing, the sync folder is unset:'
    echo '    maestral config set path ~/box'
  fi
fi
