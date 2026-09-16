#!/usr/bin/env bash
#
# Routine maintenance for an already-provisioned machine: upgrade what Homebrew
# installed, re-link the repo, re-seed what drifted, and report what needs a
# decision.
#
# It installs what the Brewfiles declare and nothing else: no macOS default, no
# toolchain, no sudo, so it still runs unattended on any machine whatever phases
# it was built with. `make core`, `make apps` and `make dev` remain the only
# paths that provision a machine from nothing.
#
# Not upgrading something is a decision, not an oversight:
#
#   mise config.toml   the language toolchains (node, python, go, uv and the
#                      typescript pair). A working toolchain buys nothing from a
#                      global bump, and project-local pins resolve independently
#                      of them anyway. What mise/.config/mise/conf.d/ declares IS
#                      upgraded: those were Homebrew formulae that `brew upgrade`
#                      kept current until Intel lost its bottles
#   uv tools           same reasoning as the toolchains above
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
# mise lives in ~/.local/bin, which only .zshrc adds; a non-interactive `ssh host
# make update` or a cron shell would otherwise skip the whole mise section.
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

# Upgrade what is installed, then install what the Brewfiles gained since the
# last pass. The install half used to be absent on the grounds that this script
# provisions nothing, and the cost was silence: an entry added to a Brewfile on
# one machine reached the others only through a full `make apps` / `make dev`,
# which is not what anyone runs on a Tuesday, so it simply never arrived.
#
# The trade that comes with it: this converges a machine to every Brewfile,
# so the first run on a core-only machine installs the GUI apps and the dev
# tools too. That is the intended behaviour, not an oversight.
BREWFILES=(brew/Brewfile brew/Brewfile.dev)
# The leaf files, for the tap scan only: `brew/Brewfile` just instance_evals
# base and apps, so it names no tap itself. Globbed rather than listed so a new
# leaf Brewfile is covered without a second edit here.
BREWFILE_LEAVES=(brew/Brewfile.*)

# What `brew bundle` would install, as its own one-line-per-entry prose
# ("Formula awscli needs to be installed or updated."). Also the fast path:
# check only dependency-resolves, so a satisfied Brewfile costs a second rather
# than the minutes a no-op `brew bundle` spends re-resolving every cask.
#
# stderr is folded in because that is where `check --verbose` puts those lines,
# not stdout. The arrow prefix is what separates them from everything else that
# lands there, e.g. a tap's `postflight` deprecation warning.
brew_bundle_missing() {
  HOMEBREW_NO_AUTO_UPDATE=1 brew bundle check --file "$1" --verbose 2>&1 |
    sed -n 's/^→ //p'
}

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
  # Reported first: until a tap is trusted, brew cannot even tell whether its
  # formulae are installed, so the "would install" list below overstates by
  # every entry those taps own.
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

  # Before the bundle, not as part of provisioning: trust.json is machine-local,
  # so a machine provisioned before its Brewfile gained a tap - or before brew
  # had `trust` at all - reaches this point untrusted, and every pass then tries
  # to install that tap's formulae and fails on them. Idempotent and silent.
  trust_brewfile_taps "${BREWFILE_LEAVES[@]}"

  # After the upgrade, so anything installed here arrives current and is not
  # immediately outdated by the pass that just ran. Streams for the same reason
  # `brew upgrade` does, and is non-fatal for the same reason opinionated-flow.sh
  # makes it non-fatal: bundle keeps going past a bad entry, installs the rest,
  # then exits non-zero with a summary.
  for brewfile in "${BREWFILES[@]}"; do
    [[ -n "$(brew_bundle_missing "$brewfile")" ]] || continue
    section "brew bundle: $brewfile"
    brew bundle --file "$brewfile" || fail "brew bundle --file $brewfile failed"
  done
fi

# tailscaled runs as a root LaunchDaemon (tailscale-up.sh starts it that way
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

# ---------------------------------------------------------------- mise

# What conf.d/ declares is tracked to latest; config.toml is the frozen set
# (node, python, go, uv, the typescript pair), where a global bump buys nothing.
#
# This is not a new policy so much as a restored one. neovim, yazi, fzf,
# fastfetch, sevenzip, gh and pi were all Homebrew formulae until Homebrew moved
# Intel macOS to Tier 3 and stopped shipping x86_64 bottles; `brew upgrade` two
# sections up is what used to keep them current, and moving them to mise took
# them off that path without anyone deciding to.
#
# Never --bump: `mise upgrade` honours whatever range each entry asks for, so
# the deliberate @playwright/cli pin cannot move by accident. check-pins.sh is
# what reports when that pin can be lifted.
mise_tracked_tools() {
  sed -n 's/^[[:space:]]*"\([^"]*\)"[[:space:]]*=.*/\1/p' \
    "$REPO_ROOT"/mise/.config/mise/conf.d/*.toml 2>/dev/null
}

# mise itself first: it is the thing that upgrades everything below, and
# install-mise.sh pins nothing, so it tracks upstream. It was the one tool on
# the machine that nothing updated once it stopped being a formula.
if [[ "$DRY_RUN" == 1 ]]; then
  section "mise"
  bash scripts/install-mise.sh --dry-run
else
  bash scripts/install-mise.sh >"$LOG" 2>&1 || fail "mise install failed."
  report mise 'already at version'
fi

if command -v mise >/dev/null 2>&1; then
  # Intersect with what is installed: `mise upgrade X` on a tool that is not
  # installed installs it (mise outdated shows it as [MISSING]), so passing the
  # whole conf.d list would give a core-only machine the dev tools on the first
  # `make update`. The Brewfiles above are converged deliberately; mise's split
  # between the core group and the dev one is not, because nothing here can tell
  # a tool that was never wanted from one that is merely not installed yet.
  MISE_INSTALLED="$(mise ls --installed 2>/dev/null | awk '{print $1}')"
  MISE_TOOLS=()
  while IFS= read -r mise_tool; do
    [[ -n "$mise_tool" ]] || continue
    grep -qxF "$mise_tool" <<<"$MISE_INSTALLED" && MISE_TOOLS+=("$mise_tool")
  done < <(mise_tracked_tools)

  if [[ "${#MISE_TOOLS[@]}" -eq 0 ]]; then
    fail "none of the tools in mise/.config/mise/conf.d/*.toml is installed; nothing was upgraded."
  elif [[ "$DRY_RUN" == 1 ]]; then
    # No section header: the install-mise.sh dry run above already opened one.
    # outdated is read-only and prints nothing when everything is current.
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

# ------------------------------------------------------- pinned outside brew

# Both are pinned outside brew: alacritty because the cask is disabled, fliqlo
# because macos-bootstrap.sh needs the bundle before Brewfile.apps would run.
# Each is a no-op unless VERSION in its script changed, which is how a
# deliberate bump on one machine reaches the others after a pull. mise is the
# third of this kind and is handled in its own section above, where it can be
# upgraded before the tools it manages.
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

# ---------------------------------------------------------------- stow

# The unfolded packages (~/.claude/skills, ~/.pi/agent/skills, ~/.config/mpv)
# get per-file symlinks rather than one
# folded dir, so a file added upstream is invisible on this machine until
# something restows.
#
# `stow -R` relinks everything it owns on every run, and with -v says so: an
# UNLINK+LINK pair per link, each tagged "(reverts previous action)". That is
# ~90 lines of churn on a machine that is already correct. Drop those pairs and
# what remains is links that genuinely appeared, vanished, or conflicted.
#
# Buffered per invocation rather than over the whole run, because paths repeat
# across targets: `skills` is stowed to ~/.claude/skills and ~/.pi/agent/skills
# under identical names, so a global "this path was a no-op" flag would hide a
# genuinely missing link in another target. restow.sh's
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
# the detail matters. So the conflict block is printed alongside the changes -
# restow.sh stows one package at a time, so the rest of the run linked normally
# and its churn is still worth filtering out.
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

# ---------------------------------------------------------------- seeds

# The files the repo cannot own outright, each stale in its own way.

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
# identity, this machine's pi search keys - so the example is a starting point
# and never a source of truth. Create it when missing; when it already exists, say
# which keys the example has gained since and leave the merge to you.
git_keys() { git config -f "$1" --list --name-only 2>/dev/null | sort -u; }

# Leaf scalar paths from a JSON object, dotted so a nested key reads as
# section.key. Enough for the flat pi web-search config.
json_keys() {
  jq -r 'paths(scalars) | map(tostring) | join(".")' "$1" 2>/dev/null | sort -u
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

# Machine-local for the same reason the two files below are, and re-linked here
# rather than only in the restore-*-settings.sh scripts because `make dev` is not
# what anyone runs after the brew step above upgrades herdlet.
if [[ "$DRY_RUN" == 1 ]]; then
  herdlet_links="$(bash scripts/link-herdlet.sh --dry-run)"
else
  herdlet_links="$(bash scripts/link-herdlet.sh)" ||
    fail "could not link herdlet's extension and skill."
fi
[[ -n "$herdlet_links" ]] && SEED_LINES+=("$(printf '%s\n' "$herdlet_links" | sed 's/^/  /')")

seed_or_diff "$HOME/.gitconfig.local" "$REPO_ROOT/git/.gitconfig.local.example" \
  git_keys "edit ~/.gitconfig.local: it still holds the example identity."
seed_or_diff "$HOME/.pi/agent/web-search.json" "$REPO_ROOT/pi/.pi/agent/web-search.json.example" \
  json_keys "review ~/.pi/agent/web-search.json: it was just seeded from the example."

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
