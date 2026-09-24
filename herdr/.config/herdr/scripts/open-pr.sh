#!/usr/bin/env bash
# Open the current branch's PR, falling back to the branch or repo page, and copy the URL.
set -euo pipefail

herdr="${HERDR_BIN_PATH:-herdr}"
pane="${HERDR_ACTIVE_PANE_ID:-}"

say() { "$herdr" notification show "open-pr" --body "$1" --sound none >/dev/null 2>&1 || true; }
die() { say "$1"; exit 0; }

[ -n "$pane" ] || die "no active pane"
command -v gh >/dev/null 2>&1 || die "gh not installed"

info=$("$herdr" pane get "$pane" 2>/dev/null) || die "cannot read $pane"
cwd=$(printf '%s' "$info" | jq -r '.result.pane.foreground_cwd // .result.pane.cwd // empty')
[ -d "$cwd" ] || die "pane has no directory"
cd -- "$cwd"
git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repo: $cwd"

# Detached worktrees have no branch for gh to match, so a leading number in the pane or tab label names the PR.
tab=$(printf '%s' "$info" | jq -r '.result.pane.tab_id // empty')
pr=$( {
  printf '%s' "$info" | jq -r '.result.pane.label // empty'
  [ -n "$tab" ] && "$herdr" tab get "$tab" 2>/dev/null | jq -r '.result.tab.label // empty'
} | grep -o -E '^[0-9]+' | head -n1 || true)

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

# The server keeps the env of whatever started it, so SSH_CONNECTION can't tell whether the viewer is local.
# Open wherever `open` exists and always copy, which clip.sh also forwards to SSH viewers.
opened=
command -v open >/dev/null 2>&1 && open "$url" 2>/dev/null && opened=1
if "$HOME/dotfiles/scripts/clip.sh" "$url"; then
  say "${opened:+opened and }copied $what $url"
elif [ -n "$opened" ]; then
  say "opened $what $url"
else
  say "could not open or copy $url"
fi
