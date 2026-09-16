#!/usr/bin/env bash
set -uo pipefail

# Wire the pieces herdlet ships inside its keg - the pi extension and the agent
# skill - into ~/.pi/agent and ~/.claude/skills.
#
# Machine-local, never stowed, and that is the whole point. Each link has to
# name a Homebrew prefix (/opt/homebrew on arm64, /usr/local on Intel), so it
# can only be absolute, and an absolute symlink inside a stow package is a
# mistake in two different ways:
#
#   - stow refuses to stow one and aborts the entire invocation. A committed
#     pi/.pi/agent/extensions/herdlet.ts cost one machine its aerospace,
#     sketchybar and claude links, which had nothing to do with it
#   - skills/herdlet/SKILL.md dodged that only because stow folds a whole skill
#     directory into one link and never descends into it. It still pointed at
#     /opt/homebrew on an Intel machine, where that path does not exist, so the
#     skill was dangling on exactly the arch nobody would think to check
#
# Both got committed the same way: ~/.claude/skills/herdlet and
# ~/.pi/agent/extensions were stow links into the repo when `herdlet setup` ran,
# so its writes landed in the checkout. Creating these as real directories is
# what keeps a future `herdlet setup` out of the repo.
#
# `herdlet setup` writes the same links, plus hooks and Claude permissions. This
# does only the part that has to survive a fresh checkout, and links into the
# keg rather than copying, so a herdlet upgrade carries the content with it.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

DRY_RUN=0
case "${1:-}" in
  --dry-run|-n) DRY_RUN=1 ;;
esac

command -v brew >/dev/null 2>&1 || exit 0

KEG="$(brew --prefix herdlet 2>/dev/null)/share/doc/herdlet"
# Not installed here: nothing to link, and nothing to say about it.
[[ -d "$KEG" ]] || exit 0

LINKED=()

link_into_keg() {  # link_into_keg <src-basename> <dest>
  local src="$KEG/$1" dest="$2" dir
  [[ -f "$src" ]] || return 0
  [[ "$(readlink "$dest" 2>/dev/null)" == "$src" ]] && return 0

  # A real file here is somebody else's - an older herdlet that copied instead
  # of linking, or a hand edit. Replacing it silently would lose it.
  if [[ -e "$dest" && ! -L "$dest" ]]; then
    warn "$dest is a regular file; leaving it alone. Remove it to pick up the herdlet keg's copy."
    return 0
  fi

  if [[ "$DRY_RUN" == 1 ]]; then
    LINKED+=("$dest")
    return 0
  fi

  # A machine that carried the old committed skill has ~/.claude/skills/herdlet
  # as a stow link to a directory the repo no longer has. `stow -R` clears those,
  # but a standalone restore-*-settings.sh run does not, and `mkdir -p` refuses
  # to work through a dangling symlink.
  dir="$(dirname "$dest")"
  [[ -L "$dir" && ! -d "$dir" ]] && rm -f "$dir"

  mkdir -p "$dir"
  ln -sfn "$src" "$dest" || { err "could not link $dest"; return 1; }
  LINKED+=("$dest")
}

rc=0
link_into_keg pi-herdlet.ts "$HOME/.pi/agent/extensions/herdlet.ts" || rc=1
# Both agents read the same skill, from their own skills dir. A directory each,
# not a link to the keg's doc dir: that one also holds a README and two other
# agents' extensions, and a skill dir should hold a skill.
link_into_keg SKILL.md "$HOME/.claude/skills/herdlet/SKILL.md" || rc=1
link_into_keg SKILL.md "$HOME/.pi/agent/skills/herdlet/SKILL.md" || rc=1

tilde() {
  case "$1" in
    "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;;
    *) printf '%s' "$1" ;;
  esac
}

for dest in ${LINKED[@]+"${LINKED[@]}"}; do
  if [[ "$DRY_RUN" == 1 ]]; then
    echo "would link $(tilde "$dest") into the herdlet keg"
  else
    echo "linked $(tilde "$dest") into the herdlet keg"
  fi
done

exit "$rc"
