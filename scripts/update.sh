#!/usr/bin/env bash
#
# Routine maintenance for an already-provisioned machine: upgrade what is
# installed, install what the repo gained since last time, and re-link.
#
# Not a bootstrap. It assumes brew/stow/mise already exist; use `make` for a
# fresh machine.
#
# Every step is non-fatal. A run that upgrades brew and then loses the network
# should still restow, so one failure never costs you the rest of the pass.
#
# Quiet by default: a step that had nothing to do prints nothing, not even its
# header, so a no-op pass is a few lines instead of a screenful. Two mechanisms,
# preferring the first because it cannot hide a real change behind a stale
# pattern:
#
#   probe   ask whether there is work (`mise outdated`, `brew outdated`,
#           `stow -n`) and skip the step entirely when there is not
#   filter   run it, then drop output lines that are known no-ops
#            (tpm's `Already installed "x"`, and so on)
#
# Quiet is about the report, not about liveness: a step whose output is buffered
# still shows a one-line progress indicator on the terminal while it runs, and
# erases it when it finishes. See capture() below.
#
# `--verbose` prints every step's raw output. `--dry-run` reports what would
# happen without changing anything, using each tool's own simulation.

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/lib.sh"

cd "$REPO_ROOT"

DRY_RUN=0
VERBOSE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run|-n) DRY_RUN=1 ;;
    --verbose|-v) VERBOSE=1 ;;
    -h|--help)
      echo "Usage: $(basename "$0") [--dry-run|-n] [--verbose|-v]"
      echo "  --dry-run, -n  Report what would change, touching nothing."
      echo "  --verbose, -v  Print every step's output, including no-ops."
      exit 0
      ;;
    *) err "unknown option: $1"; exit 1 ;;
  esac
  shift
done

[[ "$DRY_RUN" == 1 ]] &&
  echo "DRY RUN: nothing will be installed, upgraded, pruned, or re-linked."

STEP_LOG="$(mktemp)"
trap 'tick_stop; rm -f "$STEP_LOG"' EXIT

# Print the command instead of running it (dry run only).
run() {
  if [[ "$DRY_RUN" == 1 ]]; then
    echo "  would run: $*"
  else
    "$@"
  fi
}

# Buffering the output also buffers the only evidence the step is alive, and a
# `brew upgrade` that has to build a bottle from source runs for 20 minutes. So
# while a captured step runs, hold one self-erasing line on the terminal: what
# is running, for how long, and the last `==>` the step wrote to the buffer.
# stderr and tty-only, so a piped or redirected run prints exactly what it did
# before, and a step that finishes in under a second still says nothing.
CAPTURE_PROGRESS=1
TICK_PID=""

tick() {
  local label="$1" start="$SECONDS" secs elapsed note
  while :; do
    sleep 1
    secs=$((SECONDS - start))
    if ((secs >= 60)); then elapsed="$((secs / 60))m$((secs % 60))s"; else elapsed="${secs}s"; fi
    note="$(grep -a '==>' "$STEP_LOG" 2>/dev/null | tail -1 |
      sed $'s/\033\[[0-9;]*m//g; s/.*==> //; s/\r//g')"
    printf '\r\033[K  %s... %s%s' "$label" "$elapsed" "${note:+  ${note:0:60}}" >&2
  done
}

tick_stop() {
  [[ -n "$TICK_PID" ]] || return 0
  kill "$TICK_PID" 2>/dev/null
  wait "$TICK_PID" 2>/dev/null
  TICK_PID=""
  printf '\r\033[K' >&2
}

# A step is named by its command, not its arguments: `brew upgrade` reads better
# than the 40 package names that follow it, and a `bash scripts/x.sh` step is
# only ever interesting as x.sh.
step_label() {
  local cmd="${1##*/}"
  case "$cmd" in
    bash|sh|zsh) printf '%s' "${2##*/}" ;;
    *) printf '%s%s' "$cmd" "${2:+ $2}" ;;
  esac
}

# capture: run a step with its output buffered, preserving its exit status so
# the caller can still `|| fail`.
capture() {
  local rc
  if [[ "$CAPTURE_PROGRESS" == 1 && -t 2 ]]; then
    tick "$(step_label "$@")" &
    TICK_PID=$!
  fi
  "$@" >"$STEP_LOG" 2>&1
  rc=$?
  tick_stop
  return "$rc"
}

# flush <section> [noise-ere]: print the buffered output, and the section
# header above it, only if any line survives the noise filter. --verbose keeps
# everything. Either way the buffer is emptied.
flush() {
  local sec="$1" noise="${2:-}" body
  if [[ "$VERBOSE" == 1 || -z "$noise" ]]; then
    body="$(cat "$STEP_LOG")"
  else
    # capture folds stderr into the log, so a sub-script's own warn()/err()
    # lands here too. Exempt those from the noise pattern unconditionally: a
    # filter tuned for chatter must never be able to hide a warning.
    body="$(awk -v noise="$noise" '/SETUP_(WARN|ERROR)/ || $0 !~ noise' "$STEP_LOG")"
  fi
  body="$(printf '%s\n' "$body" | sed '/^[[:space:]]*$/d')"
  if [[ -n "$body" ]]; then
    section "$sec"
    printf '%s\n' "$body"
  fi
  : >"$STEP_LOG"
}

# keep <ere>: reduce the buffer to just the matching lines, for a step whose
# output is better described by what to show than by what to drop. No-op under
# --verbose.
keep() {
  [[ "$VERBOSE" == 1 ]] && return 0
  grep -E "$1" "$STEP_LOG" >"$STEP_LOG.keep" 2>/dev/null
  mv -f "$STEP_LOG.keep" "$STEP_LOG"
  return 0
}

# A pass over ~15 tools prints far more than anyone reads, and the two or three
# lines that need a decision scroll away. So anything actionable is collected
# and reprinted as one block at the end - the same shape opinionated-flow.sh
# uses for its brew failures and next steps.
ATTENTION=()

# fail: warn now (the failure needs its surrounding context to make sense) and
# again in the summary. note: summary only, for things that are working as
# intended but still want a decision.
fail() {
  warn "$*"
  ATTENTION+=("$*")
}
note() { ATTENTION+=("$*"); }

# Pulling is left to you: an automatic pull into a dirty tree or onto a local
# commit is a worse surprise than a stale run. Just make "you are behind"
# impossible to miss, because everything below re-links from the checkout.
if git fetch --quiet origin 2>/dev/null; then
  upstream="$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || true)"
  if [[ -n "$upstream" ]]; then
    behind="$(git rev-list --count "HEAD..$upstream" 2>/dev/null || echo 0)"
    if [[ "$behind" -gt 0 ]]; then
      section "repo"
      fail "$behind commit(s) behind $upstream; 'git pull' first or this run re-links stale files."
    elif [[ "$DRY_RUN" == 1 || "$VERBOSE" == 1 ]]; then
      section "repo"
      echo "  up to date with $upstream"
    fi
  fi
else
  section "repo"
  fail "could not fetch; skipping the behind-check"
fi

# tailscale is held back deliberately. It runs as a root LaunchDaemon (see
# opinionated-flow.sh:171), so a brew upgrade leaves root-owned paths that need
# a manual `sudo rm` - not something an unattended update should trigger.
tailscale_outdated() { brew outdated --quiet 2>/dev/null | grep -qx tailscale; }
upgradable() { brew outdated --quiet 2>/dev/null | grep -vx tailscale; }
bundle_satisfied() {
  HOMEBREW_NO_AUTO_UPDATE=1 brew bundle check --file "$1" >/dev/null 2>&1
}

if [[ "$DRY_RUN" == 1 ]]; then
  section "brew"
  # No `brew update` first: it rewrites tap metadata, which is a change. So this
  # lists what is outdated as of the last update, not as of this second.
  outdated="$(upgradable)"
  if [[ -n "$outdated" ]]; then
    # A count, not 60 package names: the list is rarely the thing you are
    # deciding about, and `brew outdated` is right there when it is.
    echo "  would upgrade $(grep -c . <<<"$outdated") packages (brew outdated for the list)"
  else
    echo "  nothing outdated (as of the last 'brew update')"
  fi
  for f in brew/Brewfile brew/Brewfile.dev; do
    missing="$(brew bundle check --file "$f" 2>&1 | sed -n 's/^ *-> //p')"
    [[ -n "$missing" ]] && echo "  would install from $f:" && printf '    %s\n' $missing
  done
else
  # `brew update` prints tap churn on every run and says nothing about whether
  # anything here needs upgrading, so it is only shown when it actually fails.
  if ! capture brew update; then
    flush brew
    fail "brew update failed"
  else
    : >"$STEP_LOG"
  fi
  outdated="$(upgradable)"
  if [[ -n "$outdated" ]]; then
    # Unquoted on purpose: one package per word is exactly the intent.
    capture brew upgrade $outdated || fail "brew upgrade failed"
    flush brew
  fi
  # bundle installs entries the repo gained since the last run; upgrade above
  # only refreshes what is already there. Neither implies the other. `check`
  # first so a satisfied Brewfile prints nothing at all.
  for f in brew/Brewfile brew/Brewfile.dev; do
    bundle_satisfied "$f" && continue
    capture brew bundle --file "$f" || fail "some entries in $f failed to install."
    flush brew
  done
fi

if tailscale_outdated; then
  note "tailscale is outdated but held back. Upgrade it deliberately:
    sudo brew services stop tailscale && brew upgrade tailscale && sudo brew services start tailscale"
fi

# Pinned outside brew because the cask is disabled; see install-alacritty.sh.
# No-ops unless VERSION there changed.
if [[ "$DRY_RUN" == 1 ]]; then
  bash scripts/install-alacritty.sh --dry-run
else
  capture bash scripts/install-alacritty.sh || fail "Alacritty install failed."
  flush alacritty 'already installed, skipping'
fi

eval "$(mise activate bash)" 2>/dev/null || true
if [[ "$DRY_RUN" == 1 ]]; then
  section "mise"
  # prune deletes every version no config references, which includes tools
  # installed ad hoc. Showing the list is the whole point of the dry run.
  echo "  would install/upgrade tools in mise/.config/mise/config.toml"
  pruned="$(mise prune --dry-run 2>&1 | awk '/uninstall/ {print $2}')"
  if [[ -n "$pruned" ]]; then
    echo "  would prune:"
    printf '    %s\n' $pruned
  else
    echo "  nothing to prune"
  fi
else
  # Two probes, so an up-to-date toolchain is silent. `mise outdated` covers
  # both floating versions moving forward and tools the config gained;
  # --dry-run-code exits non-zero only when there is something to prune.
  if [[ -n "$(mise outdated 2>/dev/null)" ]] || [[ -n "$(mise ls --missing 2>/dev/null)" ]]; then
    capture mise install || fail "some toolchains/global npm tools failed to install."
    flush mise
  fi
  if ! mise prune --dry-run-code >/dev/null 2>&1; then
    capture mise prune --yes || fail "mise prune failed"
    flush mise
  fi
fi

export PATH="$HOME/.local/bin:$PATH"
if command -v claude >/dev/null 2>&1; then
  if [[ "$DRY_RUN" == 1 ]]; then
    section "apps"
    run claude update
    run claude plugin marketplace update
  else
    capture claude update || fail "claude update failed"
    flush apps 'up to date|up-to-date|already'
    # The bootstrap adds claude-plugins-official once; without this its skills
    # stay pinned to whatever the marketplace held on provisioning day.
    capture claude plugin marketplace update || fail "marketplace update failed"
    flush apps 'up to date|up-to-date|already|No changes'
  fi
fi
if command -v maestral >/dev/null 2>&1; then
  if [[ "$DRY_RUN" == 1 ]]; then
    run mise exec -- uv tool upgrade maestral
  else
    capture mise exec -- uv tool upgrade maestral || fail "maestral upgrade failed"
    flush apps 'is already up-to-date|Nothing to upgrade'
  fi
fi

# TPM clones each plugin as its own git repo under ~/.tmux/plugins, outside
# both brew and stow, so nothing else here touches them. install_plugins picks
# up plugins added to .tmux.conf elsewhere; update_plugins pulls the clones.
TPM_DIR="$HOME/.tmux/plugins/tpm"
if [[ -x "$TPM_DIR/bin/install_plugins" ]]; then
  if [[ "$DRY_RUN" == 1 ]]; then
    section "tmux"
    run "$TPM_DIR/bin/install_plugins"
    run "$TPM_DIR/bin/update_plugins" all
  else
    capture "$TPM_DIR/bin/install_plugins" || fail "tmux plugin install failed"
    flush tmux '^Already installed'
    capture "$TPM_DIR/bin/update_plugins" all || fail "tmux plugin update failed"
    flush tmux 'Already up to date|^Updating|^"[^"]*" plugin'
  fi
elif [[ "$VERBOSE" == 1 || "$DRY_RUN" == 1 ]]; then
  section "tmux"
  echo "  tpm not installed, skipping"
fi

# Seeded rather than stowed because Package Control rewrites the file at
# runtime; re-running is how newly-curated packages and file associations
# propagate (see the script's own header).
if [[ -d "/Applications/Sublime Text.app" ]]; then
  if [[ "$DRY_RUN" == 1 ]]; then
    section "sublime"
    run bash scripts/setup-sublime.sh
  else
    capture bash scripts/setup-sublime.sh || fail "Sublime setup failed."
    flush sublime 'already bootstrapped'
  fi
elif [[ "$VERBOSE" == 1 || "$DRY_RUN" == 1 ]]; then
  section "sublime"
  echo "  Sublime Text not installed, skipping"
fi

# Defaults added on another machine only land here on a re-run. Documented as
# safe to rerun, and it has its own --dry-run. Prompts for sudo.
if [[ "$DRY_RUN" == 1 ]]; then
  section "macos"
  # Its dry-run prints every individual `defaults write` - 200+ lines that would
  # bury everything else in this report. Count them and point at the real thing.
  macos_writes="$(bash scripts/macos-bootstrap.sh --dry-run 2>&1 | grep -c '\[dry-run\]')"
  echo "  would apply $macos_writes settings"
  echo "  (scripts/macos-bootstrap.sh --dry-run for the full list)"
else
  # It writes every setting unconditionally and never compares against the
  # current value, so its per-setting output says nothing about what changed.
  # Only its own warnings and errors carry information here.
  #
  # It also runs its own `sudo -v`, whose prompt goes to the tty rather than
  # into the buffer. A repainting progress line would erase that prompt and
  # turn a password request into an apparent hang, so this step announces
  # itself once and then leaves the terminal alone.
  echo "  applying macOS defaults (may ask for your password)"
  CAPTURE_PROGRESS=0
  capture bash scripts/macos-bootstrap.sh || fail "macOS defaults failed."
  CAPTURE_PROGRESS=1
  keep 'SETUP_(WARN|ERROR)'
  flush macos
fi

# Last of the mutating steps: the unfolded packages (~/.claude/skills,
# ~/.codex/skills, ~/.config/mpv) get per-file symlinks rather than one folded
# dir, so an entry added upstream is invisible until this runs.
#
# `stow -R -n -v` emits an UNLINK+LINK pair for every link it already owns, each
# tagged "(reverts previous action)" - ~90 lines of no-op on a stowed machine.
# Dropping those pairs leaves only real changes and conflicts.
stow_changes() {
  bash scripts/restow.sh --dry-run 2>&1 | awk '
    { line[NR] = $0 }
    /^LINK: / {
      p = $0; sub(/^LINK: /, "", p); sub(/ =>.*/, "", p)
      if ($0 ~ /reverts previous action/) noop[p] = 1
    }
    END {
      for (i = 1; i <= NR; i++) {
        l = line[i]
        if (l !~ /^(UN)?LINK: /) continue
        p = l; sub(/^(UN)?LINK: /, "", p); sub(/ =>.*/, "", p)
        if (p in noop) continue
        print l
      }
    }'
}

pending_stow="$(stow_changes)"
if [[ "$DRY_RUN" == 1 ]]; then
  section "stow"
  if [[ -n "$pending_stow" ]]; then
    printf '%s\n' "$pending_stow"
  else
    echo "  no symlink changes"
  fi
elif [[ -n "$pending_stow" ]]; then
  # The simulation above already told us what will change, so a real restow
  # only runs when there is something to do.
  capture bash scripts/restow.sh || fail "restow failed"
  section "stow"
  printf '%s\n' "$pending_stow"
fi

# Read-only either way. It prints its own report in dry-run/verbose mode;
# otherwise only the actionable lines matter, and CHECK_PINS_ACTIONS collects
# those without capturing its stdout (which would strip the colors).
pins_actions="$(mktemp)"
if [[ "$DRY_RUN" == 1 || "$VERBOSE" == 1 ]]; then
  CHECK_PINS_ACTIONS="$pins_actions" bash scripts/check-pins.sh || true
else
  CHECK_PINS_ACTIONS="$pins_actions" capture bash scripts/check-pins.sh || true
  # Only surface the report when a pin has actually expired. Its own section
  # header is in the buffer too; drop it so flush's isn't a duplicate.
  [[ -s "$pins_actions" ]] && flush pins '^==> pins$' || : >"$STEP_LOG"
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
