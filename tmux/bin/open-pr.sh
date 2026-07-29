#!/usr/bin/env bash
# prefix+o: open the current pane's GitHub PR in the default browser.
# Two sources, authoritative first:
#   1. the branch checked out in the pane's cwd - gh matches it against origin's
#      open PRs, so any repo/worktree works, not just review ones
#   2. a PR number LEADING the pane label or window name (what `review <pr#>`
#      sets): covers fork PRs, whose head only exists as refs/pull/N/head and so
#      has no origin branch for (1) to match. Anchored at the start so an
#      ordinary window name ("web2", "claude-3") can't pass for a PR number.
# Call with run-shell -b: gh hits the network, and a foreground run-shell freezes
# the whole server until it returns.
set -euo pipefail

pane=${1:-}
[ -n "$pane" ] || pane=$(tmux display-message -p '#{pane_id}' 2>/dev/null || true)
[ -n "$pane" ] || { tmux display-message "open-pr: no target pane"; exit 0; }

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

say() { tmux display-message -t "$pane" "$1" 2>/dev/null || true; }
die() { say "open-pr: $1"; exit 0; }
ask() { tmux display-message -p -t "$pane" "$1" 2>/dev/null || true; }

command -v gh >/dev/null 2>&1 || die "gh not installed"

cwd=$(ask '#{pane_current_path}')
[ -d "$cwd" ] || die "pane has no directory"
cd -- "$cwd"
git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repo: $cwd"

pr=$(printf '%s\n%s\n' "$(ask '#{@pane_label}')" "$(ask '#{window_name}')" \
  | grep -o -E '^[0-9]+' | head -n1 || true)

# --json (not --web) so a missing PR fails here instead of opening a 404, and so
# the message can name what got opened
errs=$(mktemp)
trap 'rm -f "$errs"' EXIT

url=$(gh pr view --json url --jq .url 2>"$errs" || true)
if [ -z "$url" ] && [ -n "$pr" ]; then
  url=$(gh pr view "$pr" --json url --jq .url 2>"$errs" || true)
fi
# gh's own wording beats a generic miss: separates "no PR for this branch" from
# expired auth or a network failure
[ -n "$url" ] || die "$(grep -m1 . "$errs" || echo "no PR here")"

if command -v open >/dev/null 2>&1; then
  open "$url"
elif command -v xdg-open >/dev/null 2>&1; then
  xdg-open "$url"
else
  # headless box over ssh: bounce the URL to the LOCAL clipboard instead
  printf -- '%s' "$url" | "$here/osc52-copy.sh"
  die "no browser here, copied $url"
fi

say "opening $url"
