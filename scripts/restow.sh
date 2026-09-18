#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/lib.sh"

if ! command -v stow >/dev/null 2>&1; then
  err "GNU stow is required to restow packages."
  exit 1
fi

STOW_FLAGS=(-R)
case "${1:-}" in
  --dry-run|-n)
    STOW_FLAGS+=(-n -v)
    echo "(dry run: no symlinks will be changed)" >&2
    ;;
  --verbose|-v) STOW_FLAGS+=(-v) ;;
esac

cd "$REPO_ROOT"

mkdir -p "$HOME/.config/mpv" "$HOME/.config/herdr"
mkdir -p "$HOME/.claude" "$HOME/.claude/skills"
mkdir -p "$HOME/.pi/agent" "$HOME/.pi/agent/extensions" "$HOME/.pi/agent/skills"

FAILED=()

conflict_targets() {
  sed -n \
    -e 's/^ *\* cannot stow .* over existing target \(.*\) since .*$/\1/p' \
    -e 's/^ *\* existing target is neither a link nor a directory: \(.*\)$/\1/p' \
    -e 's/^ *\* existing target is not owned by stow: \(.*\)$/\1/p'
}

have_tty() { { : >/dev/tty; } 2>/dev/null; }

resolve_conflicts() {
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

run_stow() {
  local target="$1" label="$2" log rc
  shift 2
  echo "Restowing $label" >&2

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

HOME_PKGS=(alacritty brew mpv nvim yazi zsh hammerspoon aerospace sketchybar mise claude pi vim herdr)
for pkg in "${HOME_PKGS[@]}"; do
  run_stow "$HOME" "$pkg into ~" "$pkg"
done

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

run_stow "$HOME/.claude/skills" "skills into ~/.claude/skills" skills
run_stow "$HOME/.pi/agent/skills" "skills into ~/.pi/agent/skills" skills

if [[ "${#FAILED[@]}" -gt 0 ]]; then
  err "these packages were left unstowed: ${FAILED[*]}"
  exit 1
fi

echo "Done." >&2
