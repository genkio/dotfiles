#!/usr/bin/env bash
set -uo pipefail

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
# stow into nested per-agent dirs; pi and herdr both drop extensions into
# ~/.pi/agent/extensions).
mkdir -p "$HOME/.config/mpv"
mkdir -p "$HOME/.claude" "$HOME/.claude/skills"
mkdir -p "$HOME/.pi/agent" "$HOME/.pi/agent/extensions" "$HOME/.pi/agent/skills"

FAILED=()

# stow names each conflict on its own line. The kinds a backup can fix are the
# ones where the target, not the package, is in the way:
#
#   * cannot stow dotfiles/vim/.vimrc over existing target .vimrc since neither
#     a link nor a directory and --adopt not specified      (stow 2.3+)
#   * existing target is neither a link nor a directory: .vimrc   (stow 2.2)
#   * existing target is not owned by stow: bin/foo
#
# Deliberately not matched: "source is an absolute symlink", which is the
# package's fault and no amount of moving things at the target end fixes, and
# "existing target is stowed to a different package", where the right answer is
# to work out which package should own it. Both are only reported.
#
# Paths are relative to the -t directory. One -e per wording rather than an
# alternation: BSD sed has no `\|`, and takes it as a literal pipe instead of
# erroring, so the pattern would just silently never match.
conflict_targets() {
  sed -n \
    -e 's/^ *\* cannot stow .* over existing target \(.*\) since .*$/\1/p' \
    -e 's/^ *\* existing target is neither a link nor a directory: \(.*\)$/\1/p' \
    -e 's/^ *\* existing target is not owned by stow: \(.*\)$/\1/p'
}

# Only ask when someone is there to answer. update.sh captures this script's
# stdout and stderr into a log, so the question has to go to /dev/tty or it is
# invisible; no tty at all (cron, `ssh host make update`) means report and move
# on rather than block forever.
have_tty() { { : >/dev/tty; } 2>/dev/null; }

# Back up and retry, once, with consent. The backup is a rename beside the
# original rather than a delete: a config that got there by hand is exactly the
# kind of thing worth keeping, and a stamped name never collides.
resolve_conflicts() {  # resolve_conflicts <target> <log> <pkg...>
  local target="$1" log="$2" paths stamp reply p
  shift 2

  paths="$(conflict_targets <"$log")"
  [[ -n "$paths" ]] || return 1
  [[ " ${STOW_FLAGS[*]} " == *" -n "* ]] && return 1
  have_tty || return 1

  {
    echo
    echo "stow: $* conflicts with files already at $target:"
    printf '%s\n' "$paths" | sed 's/^/  /'
    printf 'Back them up (renamed in place) and stow over them? [y/N] '
  } >/dev/tty
  read -r reply </dev/tty
  [[ "$reply" == [yY]* ]] || return 1

  stamp="$(date +%Y%m%d%H%M%S)"
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    mv "$target/$p" "$target/$p.bak-$stamp" || return 1
    echo "Backed up $target/$p -> $p.bak-$stamp" >&2
  done <<<"$paths"

  stow "${STOW_FLAGS[@]}" -t "$target" "$@"
}

# Progress goes to stderr, where `stow -v` also writes, so the two stay
# interleaved in a combined capture. A caller filtering that output needs to
# know which invocation each LINK line came from: `skills` is stowed to two
# targets under the same relative names, so without a boundary between them a
# no-op link in one target would mask a real change in the other (see the
# stow_changes filter in update.sh).
#
# stow aborts the whole invocation on one conflict ("All operations aborted"),
# so every caller here passes a single package: a committed absolute symlink in
# `pi` once cost a machine its aerospace, sketchybar and claude links, which
# had nothing to do with it and were listed as linked in the same output.
run_stow() {
  local target="$1" label="$2" log rc
  shift 2
  echo "Restowing $label" >&2

  # Captured rather than streamed, because the conflict lines have to be read
  # back before deciding anything; replayed immediately so a caller combining
  # the two streams still sees them in order.
  log="$(mktemp)"
  stow "${STOW_FLAGS[@]}" -t "$target" "$@" 2>"$log"
  rc=$?
  cat "$log" >&2

  if [[ "$rc" -ne 0 ]]; then
    resolve_conflicts "$target" "$log" "$@"
    rc=$?
    [[ "$rc" -ne 0 ]] && FAILED+=("$*")
  fi
  rm -f "$log"
  return "$rc"
}

# Packages that stow straight to $HOME with no guards.
HOME_PKGS=(alacritty brew mpv nvim tmux yazi zsh hammerspoon aerospace sketchybar mise claude pi vim)
for pkg in "${HOME_PKGS[@]}"; do
  run_stow "$HOME" "$pkg into ~" "$pkg"
done

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
run_stow "$HOME/.pi/agent/skills" "skills into ~/.pi/agent/skills" skills

# One package left unstowed is still a failure the caller must see, even though
# every other package linked - that is the whole point of stowing them apart.
if [[ "${#FAILED[@]}" -gt 0 ]]; then
  err "these packages were left unstowed: ${FAILED[*]}"
  exit 1
fi

echo "Done." >&2
