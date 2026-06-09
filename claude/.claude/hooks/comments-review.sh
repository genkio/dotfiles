#!/usr/bin/env bash
# Stop hook: if this turn added code comments (flagged by comments.sh), block the
# stop ONCE and ask THIS session to re-audit those comments against
# ~/.claude/rules/comments.md. The judge is the session model itself -> full repo
# context, no external process, no 45s codex timeout, no Agent SDK call (an
# in-session continuation, covered by the running subscription).
#
# stop_hook_active guard -> review runs at most once per turn. Without it the
# review's own edits would re-flag via comments.sh and loop.
set -u

command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)"
session_id="$(printf '%s' "$input" | jq -r '.session_id // empty')"
[ -z "$session_id" ] && exit 0

flag="${TMPDIR:-/tmp}/claude-comments-${session_id}"
[ -f "$flag" ] || exit 0

# already continuing because of a stop hook -> clear flag, don't re-block. caps
# the review at one pass and clears flags set by the review's own edits.
stop_active="$(printf '%s' "$input" | jq -r '.stop_hook_active // false')"
if [ "$stop_active" = "true" ]; then
  rm -f "$flag"
  exit 0
fi

files="$(sort -u "$flag" | grep -v '^[[:space:]]*$' | sed 's/^/  - /')"
rm -f "$flag"
[ -z "$files" ] && exit 0

reason="You added code comments this turn. Before finishing, re-read ~/.claude/rules/comments.md and audit every comment you added in these files:
$files
For each added comment, keep it only if it explains WHY (intent, tradeoff, gotcha, workaround, non-obvious constraint). Delete or rewrite any that restate WHAT the code does, narrate the obvious, or are decorative dividers, banner blocks, end-of-block markers, or bare label comments. Match the surrounding comment density and language. If every added comment already complies (or there are none), make no edits. Then finish."

jq -n --arg r "$reason" '{decision:"block", reason:$r}'
exit 0
