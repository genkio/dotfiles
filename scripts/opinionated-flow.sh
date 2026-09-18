#!/usr/bin/env bash
set -euo pipefail

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

PHASE_TIMES=()
phase_start() { PHASE_T0=$SECONDS; section "$1"; }
phase_end() { PHASE_TIMES+=("$(printf '%-8s %4ds' "$1" "$((SECONDS - PHASE_T0))")"); }

SUDO_KEEPALIVE_PID=""
cleanup() {
  if [[ -n "$SUDO_KEEPALIVE_PID" ]]; then
    kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
  fi
  unset DOTFILES_SUDO_PASSWORD DOTFILES_SUDO_WARMED
  restore_tty
}
trap cleanup EXIT

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
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

brew_bundle_install() {
  local file="$1"
  if HOMEBREW_NO_AUTO_UPDATE=1 brew bundle check --file "$file" >/dev/null 2>&1; then
    echo "brew bundle: $file already satisfied, skipping"
    return 0
  fi
  if ! brew bundle --file "$file"; then
    warn "some entries in $file failed to install; continuing setup."
    BREW_BUNDLE_FAILURES+=("$file")
  fi
}

cd "$REPO_ROOT"

if has_phase macos; then
  phase_start "macos: system preferences"
  if [[ ! -f scripts/macos-bootstrap.sh ]]; then
    err "scripts/macos-bootstrap.sh not found."
    exit 1
  fi

  MACOS_ARGS=()
  [[ -n "$COMPUTER_NAME" ]] && MACOS_ARGS+=(--name "$COMPUTER_NAME")

  DOTFILES_DEFER_TOUCHID=1 bash scripts/macos-bootstrap.sh "${MACOS_ARGS[@]+"${MACOS_ARGS[@]}"}"
  phase_end macos
fi

if has_phase core; then
phase_start "core: homebrew packages, stow, tmux plugins, git"

ensure_clt_current || exit 1

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew not found. Installing..."

  BREW_INSTALL_REF=HEAD
  if [[ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null)" != "1" ]]; then
    BREW_INSTALL_REF=7a133dcc74051ee4efc79467ed215dfedf45aea2
    warn "Intel Mac: using the last Homebrew installer that supported x86_64."
    warn "Homebrew is Tier 3 there and builds most packages from source."
  fi

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
  /bin/bash "$BREW_INSTALLER" || true
  rm -f "$BREW_INSTALLER"

  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -f /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
fi

if ! command -v brew >/dev/null 2>&1; then
  err "Homebrew is still not on PATH, so the core phase cannot continue."
  err "Install it from https://brew.sh, then rerun 'make core'."
  exit 1
fi

if ! command -v stow >/dev/null 2>&1; then
  echo "GNU stow not found. Installing with Homebrew..."
  brew install stow
fi

trust_brewfile_taps brew/Brewfile.base

brew_bundle_install brew/Brewfile.base
mkdir -p "$HOME/.config/mpv"
stow -t "$HOME" brew mise mpv nvim tmux vim yazi zsh

export PATH="$HOME/.local/bin:$PATH"
bash scripts/install-mise.sh

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
  phase_start "apps: GUI casks, hammerspoon, aerospace, sketchybar, sublime"
  require_brew apps
  trust_brewfile_taps brew/Brewfile.apps
  brew_bundle_install brew/Brewfile.apps
  stow -t "$HOME" hammerspoon aerospace sketchybar
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

if has_phase touchid; then
  phase_start "touchid: pam_tid for sudo"
  if [[ -n "${SUDO_KEEPALIVE_PID:-}" ]]; then
    kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    SUDO_KEEPALIVE_PID=""
  fi
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

NEXT_STEPS=()
PLACEHOLDER_EMAIL="$(git config -f "$REPO_ROOT/git/.gitconfig.local.example" user.email 2>/dev/null || true)"
CURRENT_EMAIL="$(git config user.email 2>/dev/null || true)"
if [[ -z "$CURRENT_EMAIL" || "$CURRENT_EMAIL" == "$PLACEHOLDER_EMAIL" ]]; then
  NEXT_STEPS+=("make ssh   # SSH key + your real git identity in ~/.gitconfig.local")
fi
if command -v tailscale >/dev/null 2>&1 &&
  ! tailscale status --json 2>/dev/null | grep -q '"BackendState": *"Running"'; then
  NEXT_STEPS+=("make tailscale   # tailnet login; prints a URL to authorize in the browser")
fi
MAESTRAL_BIN="$(command -v maestral || true)"
[[ -n "$MAESTRAL_BIN" ]] || MAESTRAL_BIN="$HOME/.local/bin/maestral"
MAESTRAL_PENDING=""
if [[ -x "$MAESTRAL_BIN" ]] && ! "$MAESTRAL_BIN" auth status >/dev/null 2>&1; then
  NEXT_STEPS+=("box auth link   # Dropbox sign-in, then 'box start' and 'box autostart -Y'")
  MAESTRAL_PENDING=1
fi
if [[ ${#NEXT_STEPS[@]} -gt 0 ]]; then
  restore_tty
  echo
  echo "Still to do by hand:"
  for step in "${NEXT_STEPS[@]}"; do
    echo "  $step"
  done
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
