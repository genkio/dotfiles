#!/bin/sh

ENGINE="$CONFIG_DIR/plugins/agent-usage/agent_usage_status.py"

TMUX_OPEN_USAGE_VIEW=all
TMUX_OPEN_USAGE_CLAUDE_FABLE=1
export TMUX_OPEN_USAGE_VIEW TMUX_OPEN_USAGE_CLAUDE_FABLE

command -v python3 >/dev/null 2>&1 || exit 0

segment() {
  TMUX_OPEN_USAGE_PROVIDERS="$1" python3 "$ENGINE" 2>/dev/null | awk '
    {
      i = index($0, "#[fg=")
      if (i == 0) exit
      rest = substr($0, i + 5)
      j = index(rest, "]")
      if (j == 0) exit

      color = substr(rest, 1, j - 1)
      text = substr(rest, j + 1)
      k = index(text, "#[fg=")
      if (k > 0) text = substr(text, 1, k - 1)

      # The engine paints a failed fetch in the dim status-line color and falls
      # back to a placeholder when it has nothing cached. Drop both instead.
      if (color == "#5c5c5c") exit
      if (text == "-" || text == "-/-") exit

      sub("/", " / ", text)
      printf "%s", text
    }'
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
