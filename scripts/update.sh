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
# `--dry-run` (or `make update DRY_RUN=1`) reports without changing anything.
# It prefers each tool's own preview - `brew outdated`, `mise prune -n`,
# `stow -n`, `macos-bootstrap.sh -n` - over guessing, so the report comes from
# the thing that will do the work. Read-only probes still hit the network.

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/lib.sh"

cd "$REPO_ROOT"

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" || "${1:-}" == "-n" ]]; then
  DRY_RUN=1
  echo "DRY RUN: nothing will be installed, upgraded, pruned, or re-linked."
fi

# Print the command instead of running it. For steps where a real preview
# exists, the caller uses that instead of this.
run() {
  if [[ "$DRY_RUN" == 1 ]]; then
    echo "  would run: $*"
  else
    "$@"
  fi
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
section "repo"
if git fetch --quiet origin 2>/dev/null; then
  upstream="$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || true)"
  if [[ -n "$upstream" ]]; then
    behind="$(git rev-list --count "HEAD..$upstream" 2>/dev/null || echo 0)"
    if [[ "$behind" -gt 0 ]]; then
      fail "$behind commit(s) behind $upstream; 'git pull' first or this run re-links stale files."
    else
      echo "  up to date with $upstream"
    fi
  fi
else
  warn "  could not fetch; skipping the behind-check"
fi

section "brew"
# tailscale is held back deliberately. It runs as a root LaunchDaemon (see
# opinionated-flow.sh:171), so a brew upgrade leaves root-owned paths that need
# a manual `sudo rm` - not something an unattended update should trigger.
tailscale_outdated() { brew outdated --quiet 2>/dev/null | grep -qx tailscale; }
upgradable() { brew outdated --quiet 2>/dev/null | grep -vx tailscale; }

if [[ "$DRY_RUN" == 1 ]]; then
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
  brew update || fail "brew update failed"
  outdated="$(upgradable)"
  if [[ -n "$outdated" ]]; then
    # Unquoted on purpose: one package per word is exactly the intent.
    brew upgrade $outdated || fail "brew upgrade failed"
  else
    echo "  nothing to upgrade"
  fi
  # bundle installs entries the repo gained since the last run; upgrade above
  # only refreshes what is already there. Neither implies the other.
  for f in brew/Brewfile brew/Brewfile.dev; do
    brew bundle --file "$f" || fail "some entries in $f failed to install."
  done
fi

if tailscale_outdated; then
  echo "  tailscale held back (root LaunchDaemon)"
  note "tailscale is outdated but held back. Upgrade it deliberately:
    sudo brew services stop tailscale && brew upgrade tailscale && sudo brew services start tailscale"
fi

# Pinned outside brew because the cask is disabled; see install-alacritty.sh.
# No-ops unless VERSION there changed.
if [[ "$DRY_RUN" == 1 ]]; then
  bash scripts/install-alacritty.sh --dry-run
else
  bash scripts/install-alacritty.sh || fail "Alacritty install failed."
fi

section "mise"
eval "$(mise activate bash)" 2>/dev/null || true
if [[ "$DRY_RUN" == 1 ]]; then
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
  # `latest` re-resolves on install, so this both adds new tools and moves the
  # floating ones forward. prune then drops the versions nothing references.
  mise install || fail "some toolchains/global npm tools failed to install."
  mise prune --yes || fail "mise prune failed"
fi

section "apps"
export PATH="$HOME/.local/bin:$PATH"
if command -v claude >/dev/null 2>&1; then
  run claude update || fail "claude update failed"
  # The bootstrap adds claude-plugins-official once; without this its skills
  # stay pinned to whatever the marketplace held on provisioning day.
  run claude plugin marketplace update || fail "marketplace update failed"
fi
command -v maestral >/dev/null 2>&1 &&
  { run mise exec -- uv tool upgrade maestral || fail "maestral upgrade failed"; }

# TPM clones each plugin as its own git repo under ~/.tmux/plugins, outside
# both brew and stow, so nothing else here touches them. install_plugins picks
# up plugins added to .tmux.conf elsewhere; update_plugins pulls the clones.
section "tmux"
TPM_DIR="$HOME/.tmux/plugins/tpm"
if [[ -x "$TPM_DIR/bin/install_plugins" ]]; then
  run "$TPM_DIR/bin/install_plugins" || fail "tmux plugin install failed"
  run "$TPM_DIR/bin/update_plugins" all || fail "tmux plugin update failed"
else
  echo "  tpm not installed, skipping"
fi

# Seeded rather than stowed because Package Control rewrites the file at
# runtime; re-running is how newly-curated packages and file associations
# propagate (see the script's own header).
section "sublime"
if [[ -d "/Applications/Sublime Text.app" ]]; then
  run bash scripts/setup-sublime.sh || fail "Sublime setup failed."
else
  echo "  Sublime Text not installed, skipping"
fi

# Defaults added on another machine only land here on a re-run. Documented as
# safe to rerun, and it has its own --dry-run. Prompts for sudo.
section "macos"
if [[ "$DRY_RUN" == 1 ]]; then
  # Its dry-run prints every individual `defaults write` - 200+ lines that would
  # bury everything else in this report. Count them and point at the real thing.
  macos_writes="$(bash scripts/macos-bootstrap.sh --dry-run 2>&1 | grep -c '\[dry-run\]')"
  echo "  would apply $macos_writes settings"
  echo "  (scripts/macos-bootstrap.sh --dry-run for the full list)"
else
  bash scripts/macos-bootstrap.sh || fail "macOS defaults failed."
fi

# Last of the mutating steps: the unfolded packages (~/.claude/skills,
# ~/.codex/skills, ~/.config/mpv) get per-file symlinks rather than one folded
# dir, so an entry added upstream is invisible until this runs.
section "stow"
if [[ "$DRY_RUN" == 1 ]]; then
  # `stow -R -n -v` emits an UNLINK+LINK pair for every link it already owns,
  # each tagged "(reverts previous action)" - ~90 lines of no-op on a stowed
  # machine. Drop those pairs so only real changes and conflicts survive. Run
  # scripts/restow.sh --dry-run directly for the unfiltered output.
  bash scripts/restow.sh --dry-run 2>&1 | awk '
    { line[NR] = $0 }
    /^LINK: / {
      p = $0; sub(/^LINK: /, "", p); sub(/ =>.*/, "", p)
      if ($0 ~ /reverts previous action/) noop[p] = 1
    }
    END {
      for (i = 1; i <= NR; i++) {
        l = line[i]
        if (l ~ /simulation mode/) continue
        if (l ~ /^(UN)?LINK: /) {
          p = l; sub(/^(UN)?LINK: /, "", p); sub(/ =>.*/, "", p)
          if (p in noop) continue
          changes++
        }
        print l
      }
      if (!changes) print "  no symlink changes"
    }'
else
  bash scripts/restow.sh || fail "restow failed"
fi

# Read-only either way, so it runs for real in a dry run too. It prints its own
# report; CHECK_PINS_ACTIONS collects just the actionable lines for the summary.
pins_actions="$(mktemp)"
CHECK_PINS_ACTIONS="$pins_actions" bash scripts/check-pins.sh || true
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
  echo
  section "nothing needs your attention"
fi
