#!/usr/bin/env bash
set -euo pipefail

# Restow every package this repo manages.
#
# `stow -R` removes stale symlinks and recreates current ones in one pass,
# so this picks up added, removed, and renamed files after edits to the
# dotfiles repo. Use this for routine re-stow.
#
# Does NOT run brew bundle, macOS defaults, or any installers. For a full
# machine bootstrap use `make` / `make bootstrap` / `make dev`.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/lib.sh"

if ! command -v stow >/dev/null 2>&1; then
  err "GNU stow is required to restow packages."
  exit 1
fi

# --dry-run: stow's own simulation, so the preview comes from stow's conflict
# detection rather than a guess about what it would do. -v to make it say so.
#
# --verbose: -v on a real run, so stow names every link it touches. `stow -R`
# relinks everything it owns, so most of that is churn tagged "(reverts
# previous action)"; callers that want only the real changes are expected to
# filter those pairs out (see update.sh).
STOW_FLAGS=(-R)
case "${1:-}" in
  --dry-run|-n)
    STOW_FLAGS+=(-n -v)
    echo "(dry run: no symlinks will be changed)" >&2
    ;;
  --verbose|-v) STOW_FLAGS+=(-v) ;;
esac

cd "$REPO_ROOT"

# Pre-create dirs that need to exist before stow runs so stow doesn't fold
# them as symlinks (mpv writes runtime state into its config dir; skills
# stow into nested per-agent dirs).
mkdir -p "$HOME/.config/mpv"
mkdir -p "$HOME/.claude" "$HOME/.claude/skills"
mkdir -p "$HOME/.codex" "$HOME/.codex/skills"

# Progress goes to stderr, where `stow -v` also writes, so the two stay
# interleaved in a combined capture. A caller filtering that output needs to
# know which invocation each LINK line came from: `skills` is stowed to two
# targets under the same relative names, so without a boundary between them a
# no-op link in one target would mask a real change in the other (see the
# stow_changes filter in update.sh).
run_stow() {
  local target="$1" label="$2"
  shift 2
  echo "Restowing $label" >&2
  stow "${STOW_FLAGS[@]}" -t "$target" "$@"
}

# Packages that stow straight to $HOME with no guards.
HOME_PKGS=(alacritty brew mpv nvim tmux yazi zsh hammerspoon mise claude codex vim)
run_stow "$HOME" "into ~: ${HOME_PKGS[*]}" "${HOME_PKGS[@]}"

# ssh and git: skip when a real file already exists at the target so we
# don't clobber a hand-edited config (matches opinionated-flow.sh).
if [[ -e "$HOME/.ssh/config" && ! -L "$HOME/.ssh/config" ]]; then
  echo "Skipping ssh: ~/.ssh/config exists and is not a symlink." >&2
else
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  run_stow "$HOME" "ssh into ~" ssh
fi

if [[ -e "$HOME/.gitconfig" && ! -L "$HOME/.gitconfig" ]]; then
  echo "Skipping git: ~/.gitconfig exists and is not a symlink." >&2
else
  run_stow "$HOME" "git into ~" git
fi

# Skills are stowed into nested per-agent dirs, each needs its own -t.
run_stow "$HOME/.claude/skills" "skills into ~/.claude/skills" skills
run_stow "$HOME/.codex/skills" "skills into ~/.codex/skills" skills

echo "Done." >&2
