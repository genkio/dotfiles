#!/usr/bin/env bash
# prefix+o: open the current pane's GitHub PR in the browser, or over ssh copy
# the URL to the local clipboard instead (see open-url.sh).
# Two sources, authoritative first:
#   1. the branch checked out in the pane's cwd - gh matches it against origin's
#      open PRs, so any repo/worktree works, not just review ones
#   2. a PR number LEADING the pane label or window name (what `review <pr#>`
#      sets): covers fork PRs, whose head only exists as refs/pull/N/head and so
#      has no origin branch for (1) to match. Anchored at the start so an
#      ordinary window name ("web2", "claude-3") can't pass for a PR number.
# With no PR from either source, fall back to the repo's own GitHub page.
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
# no PR (yet) is the common case on a fresh branch, so fall back to the repo's
# own page rather than failing. Derived from origin's remote URL, not
# `gh repo view`: in a fork gh resolves to the upstream repo, but prefix+o should
# land on the repo this checkout actually pushes to.
what=PR
if [ -z "$url" ]; then
  what=repo
  remote=$(git remote get-url origin 2>/dev/null || git remote get-url upstream 2>/dev/null || true)
  [ -n "$remote" ] || die "$(grep -m1 . "$errs" || echo "no PR and no remote here")"
  case "$remote" in
    ssh://*)            host_path=${remote#ssh://} ;;
    https://*|http://*) host_path=${remote#*://} ;;
    *@*:*)              host_path=$(printf '%s' "$remote" | tr ':' '/') ;;
    *) die "unrecognized remote: $remote" ;;
  esac
  host_path=${host_path#*@}          # drop any user@ (git@github.com -> github.com)
  url="https://${host_path%.git}"

  # A branch that exists on the remote is the interesting page, not the repo
  # root. Gated on the origin/<branch> ref rather than ls-remote: no network, and
  # a branch never pushed would 404. Detached HEAD and the remote's own default
  # branch both fall through to the root.
  branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)
  default=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
  if [ -n "$branch" ] && [ "${default#origin/}" != "$branch" ] \
    && git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
    url="$url/tree/$branch"
    what=branch
  fi
fi

case "$("$here/open-url.sh" "$url" "$(ask '#{client_tty}')" "$(ask '#{client_termname}')")" in
  opened) say "opening $what $url" ;;
  copied) say "no browser here, copied $what $url" ;;
esac
