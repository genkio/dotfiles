#!/usr/bin/env bash
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

errs=$(mktemp)
trap 'rm -f "$errs"' EXIT

url=$(gh pr view --json url --jq .url 2>"$errs" || true)
if [ -z "$url" ] && [ -n "$pr" ]; then
  url=$(gh pr view "$pr" --json url --jq .url 2>"$errs" || true)
fi
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
  host_path=${host_path#*@}
  url="https://${host_path%.git}"

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
