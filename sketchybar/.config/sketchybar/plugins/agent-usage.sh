#!/bin/sh

ENGINE="$CONFIG_DIR/plugins/agent-usage/agent_usage_status.py"

AGENT_USAGE_VIEW=all
AGENT_USAGE_CLAUDE_FABLE=1
export AGENT_USAGE_VIEW AGENT_USAGE_CLAUDE_FABLE

command -v python3 >/dev/null 2>&1 || exit 0

segment() {
  AGENT_USAGE_PROVIDERS="$1" python3 "$ENGINE" 2>/dev/null
}

label=""
for provider in claude codex; do
  part="$(segment "$provider")"
  [ -n "$part" ] || continue
  label="${label:+$label   }$part"
done

if [ -n "$label" ]; then
  sketchybar --set "$NAME" drawing=on label="$label"
else
  sketchybar --set "$NAME" drawing=off
fi
