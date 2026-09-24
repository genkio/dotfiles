#!/bin/sh

PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

MEMO="${TMPDIR:-/tmp}/aerospace-chrome-state"

if [ "$(aerospace list-windows --focused --format '%{window-is-fullscreen}')" = "true" ]; then
  fullscreen_display="$(aerospace list-monitors --focused \
                          --format '%{monitor-appkit-nsscreen-screens-id}')"
  want="$(aerospace list-monitors --format '%{monitor-appkit-nsscreen-screens-id}' \
            | grep -v "^${fullscreen_display}$" | paste -sd, -)"
  [ -z "$want" ] && want=none
else
  want=all
fi

if [ "$1" != force ] && [ "$(cat "$MEMO" 2>/dev/null)" = "$want" ]; then
  exit 0
fi

"$(dirname "$0")/chrome.sh" "$want"
printf '%s' "$want" > "$MEMO"
