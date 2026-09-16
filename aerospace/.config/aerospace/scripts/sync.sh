#!/bin/sh

# Every hook lands here: workspace change, focus change, fullscreen toggle, and
# sketchybarrc's own startup, which passes `force` to get past both memos.
# Both halves memoize, so calling this more often than needed is cheap.

"$(dirname "$0")/spaces-sync.sh" "$@"
"$(dirname "$0")/chrome-sync.sh" "$@"
