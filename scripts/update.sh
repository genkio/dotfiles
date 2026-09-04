#!/usr/bin/env bash
#
# Routine maintenance for an already-provisioned machine: upgrade what Homebrew
# installed, re-link the repo, re-seed what drifted, and report what needs a
# decision.
#
# Deliberately not a provisioner. It never installs a package the machine does
# not already have, never writes a macOS default, and never asks for sudo, so it
# runs unattended on any machine whatever profile it was built with (base,
# --include-apps, --include-dev). `make`, `make apps`, and `make dev` remain the
# only paths that install.
#
# Not upgrading something is a decision, not an oversight:
#
#   mise, uv tools     working toolchains buy nothing from a global bump, and
#                      project-local pins resolve independently of them anyway
#   Claude Code        updated by hand, when you pick the version
#   Oh My Zsh          self-installs from .zshrc; nothing here needs it current
#   tmux/nvim plugins  small, stable, pinned. nvim's lockfile is tracked, so
#                      updating it is a repo change, not a machine change
#   Sublime packages   Package Control updates them in-app
#   macOS defaults     ~200 unconditional writes behind a sudo prompt; rerun
#                      scripts/macos-bootstrap.sh deliberately instead
#
# Every step is non-fatal. Losing the network after the brew step should still
# restow, so one failure never costs the rest of the pass.
#
# Quiet by default: a step with nothing to report prints nothing, not even its
# header, so a no-op pass is one line. `brew upgrade` is the exception, and gets
# to stream - it is the only slow step here, and its own output is the progress
# indicator.
#
# --dry-run reports what would change, using each tool's own simulation.

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/lib.sh"

cd "$REPO_ROOT"

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

# report <section> [noise-ere]: print what the last captured step wrote, minus
# the lines that only mean "nothing happened", under a header - and only when
# something survives. Empties the buffer either way.
#
# A sub-script's own warn()/err() is exempt from the noise pattern
# unconditionally: a filter tuned for chatter must never hide a warning.
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

# Six steps print more than anyone reads when something is wrong, and the two
# lines that need a decision scroll away. Anything actionable is collected and
# reprinted as one block at the end - the shape opinionated-flow.sh uses for its
# brew failures and next steps.
ATTENTION=()

# fail: warn now (a failure needs its surrounding context to make sense) and
# again in the summary. note: summary only, for things working as intended that
# still want a decision.
fail() {
  warn "$*"
  ATTENTION+=("$*")
}
note() { ATTENTION+=("$*"); }

# ---------------------------------------------------------------- repo

# Pulling is left to you: an automatic pull into a dirty tree or onto a local
# commit is a worse surprise than a stale run. Just make "you are behind"
# impossible to miss, because every step below works from this checkout.
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

# ---------------------------------------------------------------- brew

# Upgrade only. `brew bundle` is absent on purpose: it would install every entry
# of every Brewfile, which converges a base machine to --include-all the first
# time you run this. A package added to a Brewfile reaches other machines when
# you run `make apps` / `make dev` there, deliberately.
if [[ "$DRY_RUN" == 1 ]]; then
  section "brew"
  # No `brew update` first: it rewrites tap metadata, which is a change. So this
  # lists what was outdated as of the last update, not as of this second.
  outdated="$(brew outdated --quiet 2>/dev/null)"
  if [[ -n "$outdated" ]]; then
    # The names, not just a count: on a dry run the list is exactly what you are
    # deciding about. One row rather than one per row, folded on spaces so a
    # 60-package pass neither breaks names at the edge of the terminal nor costs
    # 60 lines.
    printf '  would upgrade %s packages: %s\n' \
      "$(grep -c . <<<"$outdated")" "$(tr '\n' ' ' <<<"$outdated" | sed 's/ *$//')" |
      fold -s -w "$(tput cols 2>/dev/null || echo 100)" | sed '2,$s/^/    /'
  else
    echo "  nothing outdated (as of the last 'brew update')"
  fi
else
  # --quiet: `brew update` reports tap churn on every run and says nothing about
  # whether anything here needs upgrading. Failures still print.
  brew update --quiet >"$LOG" 2>&1 || fail "brew update failed"
  report brew
  outdated="$(brew outdated --quiet 2>/dev/null)"
  if [[ -n "$outdated" ]]; then
    section "brew"
    # Unquoted on purpose: one package per word is exactly the intent. Streams
    # rather than being captured, so a bottle that builds from source for 20
    # minutes still shows it is alive.
    brew upgrade $outdated || fail "brew upgrade failed"
  fi
fi

# tailscaled runs as a root LaunchDaemon (opinionated-flow.sh starts it that way
# so the node is reachable without anyone logging in). Upgrading the formula
# needs no privileges - the Cellar belongs to you - but two consequences do, and
# this script does not sudo. So report them and let you pick the moment:
#
#   - the daemon keeps executing the binary it started with until restarted, so
#     an upgraded keg is not actually running yet
#   - the superseded keg is left behind with root-owned files inside, which
#     `brew cleanup` (running as you) cannot remove
tailscale_followups() {
  command -v brew >/dev/null 2>&1 || return 0

  local cellar linked daemon stale=()
  cellar="$(brew --prefix 2>/dev/null)/Cellar/tailscale"
  [[ -d "$cellar" ]] || return 0

  linked="$(readlink "$(brew --prefix)/opt/tailscale" 2>/dev/null)"
  linked="${linked##*/}"
  [[ -n "$linked" ]] || return 0

  # `tailscale version --daemon` reports the running daemon separately from the
  # CLI, which is the whole point here; its long form (1.2.3-tHASH) has to be
  # trimmed back to the keg's version before comparing.
  if command -v tailscale >/dev/null 2>&1; then
    daemon="$(tailscale version --daemon 2>/dev/null | sed -n 's/^Daemon: //p')"
    daemon="${daemon%%-*}"
    if [[ -n "$daemon" && "$daemon" != "$linked" ]]; then
      note "tailscaled is still running $daemon; the installed keg is $linked. Restart it when convenient:
    sudo brew services restart tailscale"
    fi
  fi

  # Only kegs that actually contain root-owned files: anything else is an
  # ordinary leftover that a plain `brew cleanup` can handle.
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

# ---------------------------------------------------------------- alacritty

# Pinned outside brew because the cask is disabled; see install-alacritty.sh.
# A no-op unless VERSION there changed, which is how a deliberate bump on one
# machine reaches the others after a pull.
if [[ "$DRY_RUN" == 1 ]]; then
  section "alacritty"
  bash scripts/install-alacritty.sh --dry-run
else
  bash scripts/install-alacritty.sh >"$LOG" 2>&1 || fail "Alacritty install failed."
  report alacritty 'already installed, skipping'
fi

# ---------------------------------------------------------------- stow

# The unfolded packages (~/.claude/skills, ~/.codex/skills, ~/.config/mpv) get
# per-file symlinks rather than one folded dir, so a file added upstream is
# invisible on this machine until something restows.
#
# `stow -R` relinks everything it owns on every run, and with -v says so: an
# UNLINK+LINK pair per link, each tagged "(reverts previous action)". That is
# ~90 lines of churn on a machine that is already correct. Drop those pairs and
# what remains is links that genuinely appeared, vanished, or conflicted.
#
# Buffered per invocation rather than over the whole run, because paths repeat
# across targets: `skills` is stowed to both ~/.claude/skills and
# ~/.codex/skills under identical names, so a global "this path was a no-op"
# flag would hide a genuinely missing link in the second target. restow.sh's
# "Restowing ..." lines mark the boundaries.
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
    # Guard messages ("~/.gitconfig exists and is not a symlink") explain why a
    # package was left alone, which is always worth saying.
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

# A conflict ("existing target is neither a link nor a directory") is reported
# in lines the change filter is built to drop, and it is exactly the case where
# the detail matters. So a failed restow prints its whole output instead.
if [[ "$stow_rc" -ne 0 ]]; then
  section "stow"
  cat "$LOG"
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

# ---------------------------------------------------------------- seeds

# Three files the repo cannot own outright, each stale in its own way.

SEED_LINES=()
seed_say() { SEED_LINES+=("  $*"); }

# ~/.gitconfig.local reads better than /Users/you/.gitconfig.local, and the
# prefix is never the part you are looking at.
tilde() {
  case "$1" in
    "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# Generated, not copied: a cache with no local state, so it can always be
# rewritten. Without this, editing a theme in the repo leaves the colors
# Alacritty actually reads untouched until the next theme flip.
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

# The other two hold machine-local state the repo must not own - your git
# identity, this machine's Codex tweaks - so the example is a starting point and
# never a source of truth. Create it when missing; when it already exists, say
# which keys the example has gained since and leave the merge to you.
git_keys() { git config -f "$1" --list --name-only 2>/dev/null | sort -u; }

# Enough TOML for these two files: track the current [section] and qualify each
# `key =` with it, so a key added under a new section reads as section.key.
toml_keys() {
  awk '
    /^[[:space:]]*\[/ {
      sec = $0
      gsub(/^[[:space:]]*\[|\][[:space:]]*$/, "", sec)
      next
    }
    /^[[:space:]]*[A-Za-z_][A-Za-z0-9_.-]*[[:space:]]*=/ {
      k = $0
      sub(/[[:space:]]*=.*/, "", k)
      gsub(/^[[:space:]]+/, "", k)
      print (sec == "" ? k : sec "." k)
    }
  ' "$1" | sort -u
}

# seed_or_diff <target> <example> <lister> <hint>
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
    # Indented under the line above; the file is yours, so this is a report and
    # never an edit.
    printf -v missing '      %s\n' $missing
    SEED_LINES+=("${missing%$'\n'}")
  fi
}

seed_or_diff "$HOME/.gitconfig.local" "$REPO_ROOT/git/.gitconfig.local.example" \
  git_keys "edit ~/.gitconfig.local: it still holds the example identity."
seed_or_diff "$HOME/.codex/config.toml" "$REPO_ROOT/codex/.codex/config.toml.example" \
  toml_keys "review ~/.codex/config.toml: it was just seeded from the example."

if [[ "${#SEED_LINES[@]}" -gt 0 ]]; then
  section "seeds"
  printf '%s\n' "${SEED_LINES[@]}"
fi

# ---------------------------------------------------------------- pins

# Read-only either way. The two pins here exist because upstream failed a
# supply-chain check, so an auto-bumper would undo the exact thing they are for;
# what goes stale is the reason, and this reports when it expires. It prints its
# own report in dry-run mode; otherwise only the actionable lines matter, and
# CHECK_PINS_ACTIONS collects those without capturing its stdout (which would
# strip the colors).
pins_actions="$(mktemp)"
if [[ "$DRY_RUN" == 1 ]]; then
  CHECK_PINS_ACTIONS="$pins_actions" bash scripts/check-pins.sh || true
else
  CHECK_PINS_ACTIONS="$pins_actions" bash scripts/check-pins.sh >"$LOG" 2>&1 || true
  # Surface the report only when a pin has actually expired. Its own section
  # header is already in the buffer, so print it as-is rather than via report().
  if [[ -s "$pins_actions" ]]; then
    cat "$LOG"
  fi
  : >"$LOG"
fi
while IFS= read -r line; do
  [[ -n "$line" ]] && note "pin expired: $line"
done <"$pins_actions"
rm -f "$pins_actions"

# ---------------------------------------------------------------- summary

if [[ "${#ATTENTION[@]}" -gt 0 ]]; then
  echo >&2
  warn "needs your attention:"
  for item in "${ATTENTION[@]}"; do
    warn "  - $item"
  done
else
  section "up to date, nothing needs your attention"
fi
