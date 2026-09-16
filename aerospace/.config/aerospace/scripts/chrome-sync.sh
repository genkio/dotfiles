#!/bin/sh

# Match the chrome to whatever the focused window actually is. AeroSpace drops
# fullscreen the moment the window loses focus, so a bar hidden by the keypress
# that turned fullscreen on would otherwise stay hidden with nothing fullscreen.
#
# Only the fullscreen window's own display loses its bar; the others keep one.
# sketchybar numbers displays the way AppKit does, which is what AeroSpace
# reports as monitor-appkit-nsscreen-screens-id - its own monitor-id is a
# different ordering and would pick the wrong screen.
#
# on-focus-changed fires on every mouse-driven focus change (focus follows mouse
# is on), so the memo keeps the common case to one `aerospace` call per event
# and only spawns sketchybar and borders on an actual transition. The memo
# outlives the sketchybar process, which comes back with a plain visible bar, so
# sketchybarrc re-enters through `force` - otherwise a restart while a window is
# fullscreen leaves the bar showing with the memo insisting it is already hidden.

PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

MEMO="${TMPDIR:-/tmp}/aerospace-chrome-state"

if [ "$(aerospace list-windows --focused --format '%{window-is-fullscreen}')" = "true" ]; then
  fullscreen_display="$(aerospace list-monitors --focused \
                          --format '%{monitor-appkit-nsscreen-screens-id}')"
  want="$(aerospace list-monitors --format '%{monitor-appkit-nsscreen-screens-id}' \
            | grep -v "^${fullscreen_display}$" | paste -sd, -)"
  # Single monitor: no display list left to draw on, so the bar goes entirely.
  [ -z "$want" ] && want=none
else
  want=all
fi

if [ "$1" != force ] && [ "$(cat "$MEMO" 2>/dev/null)" = "$want" ]; then
  exit 0
fi

"$(dirname "$0")/chrome.sh" "$want"
printf '%s' "$want" > "$MEMO"
