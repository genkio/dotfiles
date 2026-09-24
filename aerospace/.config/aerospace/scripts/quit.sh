#!/bin/sh

PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

killall AeroSpace borders

for _ in 1 2 3 4 5 6 7 8 9 10; do
  pgrep -x AeroSpace >/dev/null || break
  sleep 0.1
done

sketchybar --trigger aerospace_state_change
