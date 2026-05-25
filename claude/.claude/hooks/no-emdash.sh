#!/usr/bin/env bash
# PreToolUse hook: block Edit/Write/NotebookEdit when the change INTRODUCES
# em-dashes (U+2014) or en-dashes (U+2013). Baseline dashes pass through:
#   - Edit:         compared against old_string
#   - Write:        compared against existing file on disk (if any)
#   - NotebookEdit: no baseline available, any dash blocks
# Enforces ~/.claude/rules/no-emdash.md without blocking edits to files that
# already contain dashes (e.g. copying user-authored prose).
set -eu

input="$(cat)"
tool_name="$(printf '%s' "$input" | jq -r '.tool_name // empty')"

count_dashes() {
  printf '%s' "$1" | LC_ALL=C grep -Fo -e '—' -e '–' | wc -l | tr -d ' '
}

new=""
old=""

case "$tool_name" in
  Edit)
    new=$(printf '%s' "$input" | jq -r '.tool_input.new_string // empty')
    old=$(printf '%s' "$input" | jq -r '.tool_input.old_string // empty')
    ;;
  Write)
    new=$(printf '%s' "$input" | jq -r '.tool_input.content // empty')
    fp=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')
    if [ -n "$fp" ] && [ -f "$fp" ]; then
      old=$(cat "$fp")
    fi
    ;;
  NotebookEdit)
    new=$(printf '%s' "$input" | jq -r '.tool_input.new_source // empty')
    ;;
  *)
    exit 0
    ;;
esac

if [ -z "$new" ]; then
  exit 0
fi

new_count=$(count_dashes "$new")
old_count=$(count_dashes "$old")

if [ "$new_count" -gt "$old_count" ]; then
  printf 'no-emdash rule: em-dash or en-dash introduced (baseline=%d, new=%d). Use period, comma, colon, parens, or hyphen (-) instead.\n' "$old_count" "$new_count" >&2
  exit 2
fi

exit 0
