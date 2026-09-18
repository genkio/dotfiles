#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/lib.sh"

MANIFEST="$REPO_ROOT/skills/remote.txt"
SKILLS_HOME="$HOME/.agents/skills"

DRY_RUN=0
UPDATE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run|-n) DRY_RUN=1 ;;
    --update) UPDATE=1 ;;
    -h|--help)
      echo "Usage: $(basename "$0") [--dry-run|-n] [--update]"
      echo "  Installs the skills listed in skills/remote.txt globally."
      echo "  --update   also pull the latest version of the ones already there."
      exit 0
      ;;
    *) err "unknown option: $1"; exit 1 ;;
  esac
  shift
done

if [[ ! -f "$MANIFEST" ]]; then
  err "$MANIFEST not found."
  exit 1
fi

if ! command -v npx >/dev/null 2>&1; then
  warn "npx not found; skipping remote skills. Install node with mise, then rerun $(basename "$0")."
  exit 0
fi

skills_cli() { npx -y skills@latest "$@"; }

PRESENT=()
while read -r pkg skill _; do
  [[ -n "$pkg" && "$pkg" != \#* ]] || continue
  if [[ -z "$skill" ]]; then
    warn "$MANIFEST: no skill name on the line for $pkg; skipping."
    continue
  fi

  if [[ -e "$SKILLS_HOME/$skill" ]]; then
    PRESENT+=("$skill")
    continue
  fi

  if [[ "$DRY_RUN" == 1 ]]; then
    echo "  would install the $skill skill from $pkg"
    continue
  fi

  echo "skills: installing $skill from $pkg..."
  skills_cli add "$pkg" --skill "$skill" \
    --agent claude-code --agent pi --global --yes >/dev/null ||
    warn "skills add $pkg --skill $skill failed; rerun scripts/install-agent-skills.sh."
done <"$MANIFEST"

if [[ "$UPDATE" == 1 && "${#PRESENT[@]}" -gt 0 ]]; then
  if [[ "$DRY_RUN" == 1 ]]; then
    echo "  would check ${PRESENT[*]} for a newer upstream version"
  else
    skills_cli update --global --yes "${PRESENT[@]}" ||
      warn "skills update failed; rerun 'npx skills update -g ${PRESENT[*]}'."
  fi
fi
