#!/usr/bin/env bash
# PreToolUse (Edit|Write|NotebookEdit): detect NEWLY ADDED code comments and flag
# them for end-of-turn self-review. No judging here -> never blocks, never calls
# an external model. The Stop hook (comments-review.sh) reads the flag and asks
# THIS session to re-audit its added comments against ~/.claude/rules/comments.md
# (WHY not WHAT) with full context -> better than a context-blind judge, and no
# 45s codex timeout / Agent SDK billing.
#
# Only *added* text is scanned, so pre-existing comments never flag:
#   - Edit:         new_string (already just the new chunk)
#   - Write new:    whole content
#   - Write exists: lines in content not in the old file (diff '>')
#   - NotebookEdit: new_source
#
# Loose by design: the cheap regex gate just decides whether to wake the review.
# False triggers (e.g. // inside a URL) cost one quick review turn where the
# model finds nothing to fix -> acceptable; precision lives in the model, not here.
set -u

command -v jq >/dev/null 2>&1 || exit 0   # need jq to parse hook input

RULE_FILE="$HOME/.claude/rules/comments.md"
[ -f "$RULE_FILE" ] || exit 0

input="$(cat)"
session_id="$(printf '%s' "$input" | jq -r '.session_id // empty')"
[ -z "$session_id" ] && exit 0   # can't scope the flag -> skip
tool_name="$(printf '%s' "$input" | jq -r '.tool_name // empty')"
file_path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')"

# skip prose/data/config/markup: this rule is about CODE comments only
ext="$(printf '%s' "$file_path" | tr '[:upper:]' '[:lower:]')"; ext="${ext##*.}"
case "$ext" in
  md|markdown|mdx|txt|text|rst|adoc|csv|tsv|json|json5|jsonc|ndjson|lock|\
  yaml|yml|toml|ini|cfg|conf|env|properties|log|svg|html|htm|xml|\
  png|jpg|jpeg|gif|webp|pdf|ico) exit 0 ;;
esac

new=""
old=""
case "$tool_name" in
  Edit)
    new=$(printf '%s' "$input" | jq -r '.tool_input.new_string // empty')
    ;;
  Write)
    new=$(printf '%s' "$input" | jq -r '.tool_input.content // empty')
    fp="$file_path"
    if [ -n "$fp" ] && [ -f "$fp" ]; then
      old=$(cat "$fp")
    fi
    ;;
  NotebookEdit)
    new=$(printf '%s' "$input" | jq -r '.tool_input.new_source // empty')
    ;;
  *) exit 0 ;;
esac

[ -z "$new" ] && exit 0

if [ -n "$old" ]; then
  delta=$(diff <(printf '%s' "$old") <(printf '%s' "$new") | grep '^>' | sed 's/^> //')
else
  delta="$new"
fi
[ -z "$delta" ] && exit 0

# cheap gate: no comment lead-in in the delta -> nothing to flag. unanchored set
# //,/*,*/,#,<!-- covers C/JS/py/etc; plus line-start --,; for lua/sql/lisp.
# anchored so statement-ending ; and i-- don't fire on every edit (trade:
# trailing inline -- / ; in those langs is missed).
markers='(//|/\*|\*/|#|<!--)'
if ! printf '%s' "$delta" | grep -qE "$markers" \
   && ! printf '%s' "$delta" | grep -qE '^[[:space:]]*(--|;)'; then
  exit 0
fi

# comment added -> flag file for the Stop hook to review (per-session; Stop dedupes)
flag="${TMPDIR:-/tmp}/claude-comments-${session_id}"
printf '%s\n' "${file_path:-(unknown file)}" >> "$flag"
exit 0
