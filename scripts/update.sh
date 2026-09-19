#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/lib.sh"

cd "$REPO_ROOT"
export PATH="$HOME/.local/bin:$PATH"

DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run|-n) DRY_RUN=1 ;;
    -h|--help)
      echo "Usage: $(basename "$0") [--dry-run|-n]"
      echo "  --dry-run, -n  Report what would change, touching nothing."
      exit 0
      ;;
    *) err "unknown option: $1"; exit 1 ;;
  esac
  shift
done

[[ "$DRY_RUN" == 1 ]] &&
  echo "DRY RUN: nothing will be upgraded, re-linked, or re-seeded."

LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

report() {
  local sec="$1" noise="${2:-}" body
  if [[ -z "$noise" ]]; then
    body="$(cat "$LOG")"
  else
    body="$(awk -v noise="$noise" '/SETUP_(WARN|ERROR)/ || $0 !~ noise' "$LOG")"
  fi
  body="$(printf '%s\n' "$body" | sed '/^[[:space:]]*$/d')"
  if [[ -n "$body" ]]; then
    section "$sec"
    printf '%s\n' "$body"
  fi
  : >"$LOG"
}

ATTENTION=()

fail() {
  warn "$*"
  ATTENTION+=("$*")
}
note() { ATTENTION+=("$*"); }

if git fetch --quiet origin 2>/dev/null; then
  upstream="$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || true)"
  if [[ -n "$upstream" ]]; then
    behind="$(git rev-list --count "HEAD..$upstream" 2>/dev/null || echo 0)"
    if [[ "$behind" -gt 0 ]]; then
      section "repo"
      fail "$behind commit(s) behind $upstream; 'git pull' first or this run re-links stale files."
    elif [[ "$DRY_RUN" == 1 ]]; then
      section "repo"
      echo "  up to date with $upstream"
    fi
  fi
else
  section "repo"
  fail "could not fetch; skipping the behind-check"
fi

BREWFILES=(brew/Brewfile brew/Brewfile.dev)
BREWFILE_LEAVES=(brew/Brewfile.*)

brew_bundle_missing() {
  HOMEBREW_NO_AUTO_UPDATE=1 brew bundle check --file "$1" --verbose 2>&1 |
    sed -n 's/^→ //p'
}

if [[ "$DRY_RUN" == 1 ]]; then
  section "brew"
  outdated="$(brew outdated --quiet 2>/dev/null)"
  if [[ -n "$outdated" ]]; then
    printf '  would upgrade %s packages: %s\n' \
      "$(grep -c . <<<"$outdated")" "$(tr '\n' ' ' <<<"$outdated" | sed 's/ *$//')" |
      fold -s -w "$(tput cols 2>/dev/null || echo 100)" | sed '2,$s/^/    /'
  else
    echo "  nothing outdated (as of the last 'brew update')"
  fi
  untrusted="$(brewfile_untrusted_taps "${BREWFILE_LEAVES[@]}")"
  if [[ -n "$untrusted" ]]; then
    printf '  would trust %s tap(s): %s\n' \
      "$(grep -c . <<<"$untrusted")" "$(tr '\n' ' ' <<<"$untrusted" | sed 's/ *$//')"
  fi
  for brewfile in "${BREWFILES[@]}"; do
    missing="$(brew_bundle_missing "$brewfile")"
    if [[ -n "$missing" ]]; then
      printf '  would install from %s:\n' "$brewfile"
      printf '%s\n' "$missing" | sed 's/^/    /'
    fi
  done
else
  brew update --quiet >"$LOG" 2>&1 || fail "brew update failed"
  report brew
  outdated="$(brew outdated --quiet 2>/dev/null)"
  if [[ -n "$outdated" ]]; then
    section "brew"
    brew upgrade $outdated || fail "brew upgrade failed"
  fi

  trust_brewfile_taps "${BREWFILE_LEAVES[@]}"

  for brewfile in "${BREWFILES[@]}"; do
    [[ -n "$(brew_bundle_missing "$brewfile")" ]] || continue
    section "brew bundle: $brewfile"
    brew bundle --file "$brewfile" || fail "brew bundle --file $brewfile failed"
  done
fi

tailscale_followups() {
  command -v brew >/dev/null 2>&1 || return 0

  local cellar linked daemon stale=()
  cellar="$(brew --prefix 2>/dev/null)/Cellar/tailscale"
  [[ -d "$cellar" ]] || return 0

  linked="$(readlink "$(brew --prefix)/opt/tailscale" 2>/dev/null)"
  linked="${linked##*/}"
  [[ -n "$linked" ]] || return 0

  if command -v tailscale >/dev/null 2>&1; then
    daemon="$(tailscale version --daemon 2>/dev/null | sed -n 's/^Daemon: //p')"
    daemon="${daemon%%-*}"
    if [[ -n "$daemon" && "$daemon" != "$linked" ]]; then
      note "tailscaled is still running $daemon; the installed keg is $linked. Restart it when convenient:
    sudo brew services restart tailscale"
    fi
  fi

  local keg
  for keg in "$cellar"/*; do
    [[ -d "$keg" && "${keg##*/}" != "$linked" ]] || continue
    [[ -n "$(find "$keg" -user root -print -quit 2>/dev/null)" ]] && stale+=("$keg")
  done
  if [[ "${#stale[@]}" -gt 0 ]]; then
    note "superseded tailscale keg(s) left root-owned, brew cleanup cannot remove them:
    sudo rm -rf ${stale[*]}"
  fi
}
tailscale_followups

mise_tracked_tools() {
  sed -n 's/^[[:space:]]*"\([^"]*\)"[[:space:]]*=.*/\1/p' \
    "$REPO_ROOT"/mise/.config/mise/conf.d/*.toml 2>/dev/null
}

if [[ "$DRY_RUN" == 1 ]]; then
  section "mise"
  bash scripts/install-mise.sh --dry-run
else
  bash scripts/install-mise.sh >"$LOG" 2>&1 || fail "mise install failed."
  report mise 'already at version'
fi

if command -v mise >/dev/null 2>&1; then
  MISE_INSTALLED="$(mise ls --installed 2>/dev/null | awk '{print $1}')"
  MISE_TOOLS=()
  while IFS= read -r mise_tool; do
    [[ -n "$mise_tool" ]] || continue
    grep -qxF "$mise_tool" <<<"$MISE_INSTALLED" && MISE_TOOLS+=("$mise_tool")
  done < <(mise_tracked_tools)

  if [[ "${#MISE_TOOLS[@]}" -eq 0 ]]; then
    fail "none of the tools in mise/.config/mise/conf.d/*.toml is installed; nothing was upgraded."
  elif [[ "$DRY_RUN" == 1 ]]; then
    outdated_mise="$(mise outdated "${MISE_TOOLS[@]}" 2>/dev/null || true)"
    if [[ -n "$outdated_mise" ]]; then
      printf '%s\n' "$outdated_mise" | sed 's/^/  /'
    else
      echo "  nothing outdated"
    fi
  else
    mise upgrade "${MISE_TOOLS[@]}" >"$LOG" 2>&1 || fail "mise upgrade failed"
    report mise 'already up to date|^$'
  fi
fi

herdr_followups() {
  command -v herdr >/dev/null 2>&1 || return 0

  local running installed
  running="$(herdr status server 2>/dev/null | sed -n 's/^version: //p')"
  [[ -n "$running" ]] || return 0
  installed="$(herdr --version 2>/dev/null | awk '{print $NF}')"
  [[ -n "$installed" && "$running" != "$installed" ]] || return 0

  note "the herdr server is still running $running; the installed binary is $installed. Restarting restores the layout and resumes agent sessions, but ends every process in it, so pick the moment:
    herdr server stop && herdr"
}
herdr_followups

herdr_refresh_integrations() {
  command -v herdr >/dev/null 2>&1 || return 0

  local target line
  for target in claude pi; do
    line="$(herdr integration status 2>/dev/null | grep -E "^$target: (current|outdated)")" ||
      continue
    if [[ "$DRY_RUN" == 1 ]]; then
      echo "would refresh the herdr $target integration ($line)"
    else
      herdr_install_integration "$target"
    fi
  done
}
herdr_refresh_integrations

if [[ "$DRY_RUN" == 1 ]]; then
  section "skills"
  bash scripts/install-agent-skills.sh --dry-run --update
else
  bash scripts/install-agent-skills.sh --update >"$LOG" 2>&1 ||
    fail "remote agent skills install failed."
  report skills 'up to date|Updating |Checking skills'
fi

if [[ "$DRY_RUN" == 1 ]]; then
  section "alacritty"
  bash scripts/install-alacritty.sh --dry-run
  section "fliqlo"
  bash scripts/install-fliqlo.sh --dry-run
else
  bash scripts/install-alacritty.sh >"$LOG" 2>&1 || fail "Alacritty install failed."
  report alacritty 'already installed, skipping'
  bash scripts/install-fliqlo.sh >"$LOG" 2>&1 || fail "Fliqlo install failed."
  report fliqlo 'already installed, skipping'
fi

stow_changes() {
  awk '
    function flush(   i, l, p) {
      for (i = 1; i <= n; i++) {
        l = buf[i]
        p = l; sub(/^(UN)?LINK: /, "", p); sub(/ =>.*/, "", p)
        if (!(p in noop)) print "  " l
      }
      n = 0
      delete noop
    }
    /^Restowing / { flush(); next }
    /^Skipping / { flush(); print "  " $0; next }
    /^(UN)?LINK: / {
      buf[++n] = $0
      if (/^LINK: / && /reverts previous action/) {
        p = $0; sub(/^LINK: /, "", p); sub(/ =>.*/, "", p); noop[p] = 1
      }
    }
    END { flush() }'
}

if [[ "$DRY_RUN" == 1 ]]; then
  bash scripts/restow.sh --dry-run >"$LOG" 2>&1
  stow_rc=$?
else
  bash scripts/restow.sh --verbose >"$LOG" 2>&1
  stow_rc=$?
fi

if [[ "$stow_rc" -ne 0 ]]; then
  section "stow"
  stow_changes <"$LOG"
  grep -E '^(WARNING!|  \*|SETUP_)' "$LOG" | sed 's/^/  /'
  fail "restow failed"
else
  changed="$(stow_changes <"$LOG")"
  if [[ -n "$changed" ]]; then
    section "stow"
    printf '%s\n' "$changed"
  elif [[ "$DRY_RUN" == 1 ]]; then
    section "stow"
    echo "  no symlink changes"
  fi
fi
: >"$LOG"

if [[ "$DRY_RUN" == 1 ]]; then
  section "clipboard bridge"
  bash scripts/install-clipboard-bridge.sh --dry-run
else
  bash scripts/install-clipboard-bridge.sh >"$LOG" 2>&1 ||
    warn "clipboard bridge not loaded; rerun scripts/install-clipboard-bridge.sh."
  : >"$LOG"
fi

SEED_LINES=()
seed_say() { SEED_LINES+=("  $*"); }

tilde() {
  case "$1" in
    "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;;
    *) printf '%s' "$1" ;;
  esac
}

theme_active="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/alacritty-theme-active.toml"
theme_before="$(shasum "$theme_active" 2>/dev/null | cut -d' ' -f1)"
if [[ "$DRY_RUN" == 1 ]]; then
  seed_say "would refresh the Alacritty theme cache for the $("$SCRIPT_DIR/current-theme.sh") theme"
else
  DOTFILES_DIR="$REPO_ROOT" bash scripts/apply-alacritty-theme.sh 2>/dev/null ||
    fail "Alacritty theme refresh failed."
  theme_after="$(shasum "$theme_active" 2>/dev/null | cut -d' ' -f1)"
  [[ "$theme_before" != "$theme_after" ]] &&
    seed_say "refreshed the Alacritty theme cache ($("$SCRIPT_DIR/current-theme.sh"))"
fi

git_keys() { git config -f "$1" --list --name-only 2>/dev/null | sort -u; }

json_keys() {
  jq -r 'paths(scalars) | map(tostring) | join(".")' "$1" 2>/dev/null | sort -u
}

seed_or_diff() {
  local target="$1" example="$2" lister="$3" hint="$4" missing

  if [[ ! -e "$target" ]]; then
    if [[ "$DRY_RUN" == 1 ]]; then
      seed_say "would seed $(tilde "$target") from ${example#"$REPO_ROOT"/}"
    else
      cp "$example" "$target" || { fail "could not seed $target"; return; }
      seed_say "seeded $(tilde "$target") from ${example#"$REPO_ROOT"/}"
      note "$hint"
    fi
    return
  fi

  missing="$(comm -23 <("$lister" "$example") <("$lister" "$target"))"
  if [[ -n "$missing" ]]; then
    seed_say "$(tilde "$target") predates these keys in ${example#"$REPO_ROOT"/}:"
    printf -v missing '      %s\n' $missing
    SEED_LINES+=("${missing%$'\n'}")
  fi
}

seed_or_diff "$HOME/.gitconfig.local" "$REPO_ROOT/git/.gitconfig.local.example" \
  git_keys "edit ~/.gitconfig.local: it still holds the example identity."
seed_or_diff "$HOME/.pi/agent/web-search.json" "$REPO_ROOT/pi/.pi/agent/web-search.json.example" \
  json_keys "review ~/.pi/agent/web-search.json: it was just seeded from the example."

if [[ "${#SEED_LINES[@]}" -gt 0 ]]; then
  section "seeds"
  printf '%s\n' "${SEED_LINES[@]}"
fi

pins_actions="$(mktemp)"
if [[ "$DRY_RUN" == 1 ]]; then
  CHECK_PINS_ACTIONS="$pins_actions" bash scripts/check-pins.sh || true
else
  CHECK_PINS_ACTIONS="$pins_actions" bash scripts/check-pins.sh >"$LOG" 2>&1 || true
  if [[ -s "$pins_actions" ]]; then
    cat "$LOG"
  fi
  : >"$LOG"
fi
while IFS= read -r line; do
  [[ -n "$line" ]] && note "pin expired: $line"
done <"$pins_actions"
rm -f "$pins_actions"

if [[ "${#ATTENTION[@]}" -gt 0 ]]; then
  echo >&2
  warn "needs your attention:"
  for item in "${ATTENTION[@]}"; do
    warn "  - $item"
  done
else
  section "up to date, nothing needs your attention"
fi
