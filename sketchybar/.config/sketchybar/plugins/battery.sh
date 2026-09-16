#!/bin/sh

# Time left, and nothing else: the charge percentage is one glance away in the
# menu bar, the hours are not. Same rule as the tmux status line
# (tmux/bin/status-usage.sh) - only while unplugged, because pmset answers
# "0:00 remaining" on AC and that reads as a flat battery.

left="$(pmset -g batt 2>/dev/null | awk '
  NR == 1 && !/Battery Power/ { exit }
  match($0, /[0-9]+:[0-9]+ remaining/) {
    split(substr($0, RSTART, RLENGTH - length(" remaining")), t, ":")
    if (t[1] + 0 == 0) printf "%dm", t[2] + 0
    else printf "%dh", t[1] + 0
    exit
  }')"

# Empty also covers the minutes after unplugging, while pmset still says
# "(no estimate)".
if [ -n "$left" ]; then
  sketchybar --set "$NAME" drawing=on label="$left"
else
  sketchybar --set "$NAME" drawing=off
fi
