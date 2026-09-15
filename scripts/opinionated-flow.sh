#!/usr/bin/env bash
set -euo pipefail

# Opinionated first-run bootstrap for this dotfiles repo.
#
# The script is intentionally a full machine setup path, not just a stow helper:
# macOS preferences, base Homebrew packages, the core stow set, tmux/git/ssh
# seeds, GUI apps and dev tooling. Each is a --phase; the caller picks which.
# Keep this aligned with AGENTS.md/CLAUDE.md before changing package names or
# setup order.
#
# Operates on its own checkout and never clones: getting this file onto the
# machine already required the repo.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
COMPUTER_NAME=""
BREW_BUNDLE_FAILURES=()

source "$SCRIPT_DIR/lib.sh"

PHASES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase)
      [[ -n "${2:-}" ]] || { err "--phase needs a name"; exit 1; }
      PHASES+=("$2")
      shift
      ;;
    --name)
      [[ -n "${2:-}" ]] || { err "--name needs a value"; exit 1; }
      COMPUTER_NAME="$2"
      shift
      ;;
    -h|--help)
      echo "Usage: $(basename "$0") --phase macos|core|apps|dev|touchid [--phase ...] [--name NAME]"
      echo "  --name NAME  Rename the machine; only the macos phase uses it."
      exit 0
      ;;
    *)
      err "unknown option: $1"
      exit 1
      ;;
  esac
  shift
done

if [[ ${#PHASES[@]} -eq 0 ]]; then
  err "no --phase given (want macos, core, apps, dev or touchid); see 'make' targets."
  exit 1
fi

# Note the run order is fixed below, not taken from the order of these flags:
# touchid genuinely has to be last (see the end of this file).
for phase in "${PHASES[@]}"; do
  case "$phase" in
    macos|core|apps|dev|touchid) ;;
    *) err "unknown phase: $phase (want macos, core, apps, dev or touchid)"; exit 1 ;;
  esac
done

require_brew() {
  command -v brew >/dev/null 2>&1 && return 0
  err "the $1 phase needs Homebrew; run 'make core' first."
  exit 1
}

has_phase() {
  local want="$1" p
  for p in "${PHASES[@]}"; do
    [[ "$p" == "$want" ]] && return 0
  done
  return 1
}

if [[ -n "$COMPUTER_NAME" ]] && ! has_phase macos; then
  warn "--name only applies to the macos phase, which is not in this run; ignoring."
fi

# Wall-clock per phase, printed at the end. The whole point of splitting the run
# up was that nobody could see where the time went.
PHASE_TIMES=()
phase_start() { PHASE_T0=$SECONDS; section "$1"; }
phase_end() { PHASE_TIMES+=("$(printf '%-8s %4ds' "$1" "$((SECONDS - PHASE_T0))")"); }

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
  # Read from /dev/tty, not stdin: with stdin redirected, `stty -echo` exits 1
  # and errexit kills the run before any message. Headless runs set
  # DOTFILES_SUDO_PASSWORD instead.
  if [[ -z "${DOTFILES_SUDO_PASSWORD:-}" ]]; then
    if ! { exec 3<>/dev/tty; } 2>/dev/null; then
      err "no terminal to ask for the sudo password; set DOTFILES_SUDO_PASSWORD for a headless run."
      exit 1
    fi
    printf 'Password (used once for sudo and FileVault): ' >&3
    stty -echo <&3
    IFS= read -r DOTFILES_SUDO_PASSWORD <&3
    stty echo <&3
    printf '\n' >&3
    exec 3>&-
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

cd "$REPO_ROOT"

# Runs first so tap-to-click etc. apply during the long brew bundle below, and
# so `softwareupdate` scheduling is off before anything competes for the uplink:
# a fresh macOS will otherwise pull a multi-GB OS update underneath the run.
# Installs nothing from Homebrew, so it works before the core phase.
if has_phase macos; then
  phase_start "macos: system preferences"
  if [[ ! -f scripts/macos-bootstrap.sh ]]; then
    err "scripts/macos-bootstrap.sh not found."
    exit 1
  fi

  MACOS_ARGS=()
  [[ -n "$COMPUTER_NAME" ]] && MACOS_ARGS+=(--name "$COMPUTER_NAME")

  # Touch ID for sudo is the one setting that must wait for the end of the whole
  # run, not just this script: see the deferred call below.
  DOTFILES_DEFER_TOUCHID=1 bash scripts/macos-bootstrap.sh "${MACOS_ARGS[@]+"${MACOS_ARGS[@]}"}"
  phase_end macos
fi

if has_phase core; then
phase_start "core: homebrew packages, stow, tmux plugins, git"

# Before Homebrew, not after: a CLT left behind by a macOS major upgrade makes
# brew reject every formula, and the run then spends twenty minutes failing one
# package at a time instead of saying the one thing that is wrong.
ensure_clt_current || exit 1

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew not found. Installing..."

  # Homebrew's installer dropped Intel on 2026-09-04 (Homebrew/install e078684,
  # "Remove Intel macOS support from installer") and now aborts outright:
  #   Homebrew on macOS is only supported on Apple Silicon processors!
  # There is no override flag. But brew ITSELF has no such check and still runs
  # on Intel - Tier 3, with removal announced for September 2027 or later - so
  # only the installer is in the way. Pin Intel to the commit before that
  # change, which still knows the /usr/local prefix; arm64 tracks HEAD.
  #
  # No check-pins.sh entry for this one: the other pins in this repo exist
  # because upstream had a problem that might get fixed, and this is the
  # opposite. Homebrew is removing Intel, not restoring it, so the audit would
  # never fire.
  #
  # sysctl rather than `uname -m`, which reports x86_64 for a terminal running
  # under Rosetta on an Apple Silicon mac and would send it down this path.
  BREW_INSTALL_REF=HEAD
  if [[ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null)" != "1" ]]; then
    BREW_INSTALL_REF=7a133dcc74051ee4efc79467ed215dfedf45aea2
    warn "Intel Mac: using the last Homebrew installer that supported x86_64."
    warn "Homebrew is Tier 3 there and builds most packages from source."
  fi

  # Fetched to a file rather than `bash -c "$(curl ...)"`. That idiom looks like
  # it fails loudly and does not: a failed curl expands to an empty string,
  # `bash -c ""` exits 0, and errexit sees a success. A DNS blip here used to
  # sail past and resurface three steps down as "brew: command not found".
  #
  # --retry-all-errors because curl does not count a name-resolution failure as
  # retryable on its own, and that is the blip most likely to happen right here:
  # the macos phase sets HostName/LocalHostName and killalls cfprefsd, so
  # resolution can be briefly unavailable while mDNSResponder catches up.
  #
  # curl's stderr is held back and only printed if every attempt fails: it
  # writes one "curl: (6) Could not resolve host" per try, so a blip that the
  # retry then recovers from otherwise looks like a failure the run ignored.
  BREW_INSTALLER="$(mktemp)"
  BREW_CURL_ERR="$(mktemp)"
  if ! curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors \
    "https://raw.githubusercontent.com/Homebrew/install/$BREW_INSTALL_REF/install.sh" \
    -o "$BREW_INSTALLER" 2>"$BREW_CURL_ERR"; then
    err "could not download the Homebrew installer, after 4 tries:"
    sed 's/^/  /' "$BREW_CURL_ERR" >&2
    err "Check with 'ping -c1 github.com', then rerun 'make core'."
    rm -f "$BREW_INSTALLER" "$BREW_CURL_ERR"
    exit 1
  fi
  rm -f "$BREW_CURL_ERR"
  # Deliberately not fatal on its own: the check below says something useful,
  # where errexit here would just exit silently mid-install.
  /bin/bash "$BREW_INSTALLER" || true
  rm -f "$BREW_INSTALLER"

  # Add brew to PATH for this session (Apple Silicon vs Intel)
  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -f /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
fi

# Everything below this line needs brew, and each failure downstream is more
# confusing than the last: `brew install stow` reports "command not found", an
# empty bundle looks satisfied, and the phase "succeeds" having done nothing.
if ! command -v brew >/dev/null 2>&1; then
  err "Homebrew is still not on PATH, so the core phase cannot continue."
  err "Install it from https://brew.sh, then rerun 'make core'."
  exit 1
fi

if ! command -v stow >/dev/null 2>&1; then
  echo "GNU stow not found. Installing with Homebrew..."
  brew install stow
fi

# carbonyl ships from third-party genkio/tap. Newer Homebrew refuses to load
# non-official tap formulae until trusted (HOMEBREW_REQUIRE_TAP_TRUST, slated to
# become default) -> `brew bundle` aborts without this. Guarded: older brew
# lacks `trust`, re-runs are no-ops.
brew tap genkio/tap >/dev/null 2>&1 || true
brew trust genkio/tap || true

brew_bundle_install brew/Brewfile.base
mkdir -p "$HOME/.config/mpv"
stow -t "$HOME" brew mise mpv nvim tmux vim yazi zsh

# Half the CLI set comes from mise, not Homebrew, so mise has to exist by the
# end of this phase and not in `dev` where it used to arrive. The reason is
# Intel: Homebrew stopped building x86_64 bottles, and neovim/yazi/fzf/
# fastfetch/sevenzip compiled from source there - yazi via rust, which means an
# llvm@22 build before the shell was usable. See conf.d/cli.toml.
#
# Stowed above first: mise only puts a tool on PATH if it is in the config, so
# installing before the config lands would leave six binaries nothing can find.
export PATH="$HOME/.local/bin:$PATH"
bash scripts/install-mise.sh

# Read the group out of the file that defines it, so adding a tool there is the
# whole change. A bare `mise install` is wrong here: it would take the dev
# toolchains in config.toml too, which is the split this phase exists to keep.
MISE_CLI=()
while IFS= read -r tool; do
  [[ -n "$tool" ]] && MISE_CLI+=("$tool")
done < <(sed -n 's/^[[:space:]]*"\([^"]*\)"[[:space:]]*=.*/\1/p' \
  mise/.config/mise/conf.d/cli.toml)
if [[ ${#MISE_CLI[@]} -eq 0 ]]; then
  warn "no tools found in mise/.config/mise/conf.d/cli.toml; skipping the CLI set."
else
  echo "mise: installing ${#MISE_CLI[@]} CLI tools (neovim, yazi, fzf, fastfetch, 7zip)..."
  mise install --quiet "${MISE_CLI[@]}" \
    || warn "some mise CLI tools failed; rerun 'mise install' later."
fi

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
if [[ -e "$HOME/.ssh/config" && ! -L "$HOME/.ssh/config" ]]; then
  echo "Skipping ssh stow: ~/.ssh/config already exists and is not a symlink."
  echo "Move it aside and run 'cd $REPO_ROOT && stow ssh' when you're ready."
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
# install_plugins shells out to tmux and exits 1 with "Tmux Plugin Manager not
# configured in tmux.conf" when it is missing, which under errexit takes the
# whole run down - so a failed `brew install tmux` upstream used to abort the
# core phase here rather than just costing plugins.
if [[ -x "$TPM_DIR/bin/install_plugins" ]]; then
  if ! command -v tmux >/dev/null 2>&1; then
    warn "tmux is not installed; skipping tmux plugin install."
  elif "$TPM_DIR/bin/install_plugins"; then
    echo "Installed tmux plugins from ~/.tmux.conf"
  else
    warn "tmux plugin install failed; run '$TPM_DIR/bin/install_plugins' later."
  fi
fi

if [[ -e "$HOME/.gitconfig" && ! -L "$HOME/.gitconfig" ]]; then
  echo "Skipping git stow: ~/.gitconfig already exists and is not a symlink."
  echo "Move it aside and run 'cd $REPO_ROOT && stow git' when you're ready."
else
  stow -t "$HOME" git
  if [[ ! -e "$HOME/.gitconfig.local" ]]; then
    cp "$REPO_ROOT/git/.gitconfig.local.example" "$HOME/.gitconfig.local"
    echo "Seeded ~/.gitconfig.local from $REPO_ROOT/git/.gitconfig.local.example"
    echo "Edit ~/.gitconfig.local for your private Git identity."
  fi
fi

phase_end core
fi

if has_phase apps; then
  phase_start "apps: GUI casks, hammerspoon, sublime"
  require_brew apps
  brew_bundle_install brew/Brewfile.apps
  stow -t "$HOME" hammerspoon
  # Non-fatal: a failed Package Control download shouldn't abort provisioning.
  bash scripts/setup-sublime.sh \
    || warn "Sublime Package Control setup failed; run 'make sublime' later."
  phase_end apps
fi

if has_phase dev; then
  phase_start "dev: dev tools, mise toolchains, coding agents"
  require_brew dev
  bash scripts/setup-dev.sh
  phase_end dev
fi

# Deliberately last: pam_tid makes sudo ask for a fingerprint, which the piped
# password cannot answer, so nothing that sudos may follow. The keepalive is the
# main offender - it re-authenticates every 60s, and every `brew` call resets the
# timestamp, so it would pop a Touch ID prompt over and over.
if has_phase touchid; then
  phase_start "touchid: pam_tid for sudo"
  if [[ -n "${SUDO_KEEPALIVE_PID:-}" ]]; then
    kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    SUDO_KEEPALIVE_PID=""
  fi
  # sudo_pw feeds the password on stdin, so the dead keepalive costs it nothing
  bash scripts/touchid-sudo.sh || warn "Touch ID for sudo not configured; rerun 'bash scripts/touchid-sudo.sh'"
  phase_end touchid
fi

if [[ ${#PHASE_TIMES[@]} -gt 0 ]]; then
  echo
  echo "Phase times:"
  printf '  %s\n' "${PHASE_TIMES[@]}"
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
PLACEHOLDER_EMAIL="$(git config -f "$REPO_ROOT/git/.gitconfig.local.example" user.email 2>/dev/null || true)"
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
