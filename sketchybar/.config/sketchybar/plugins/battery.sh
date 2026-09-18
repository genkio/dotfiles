#!/bin/sh

left="$(pmset -g batt 2>/dev/null | awk '
  NR == 1 && !/Battery Power/ { exit }
  match($0, /[0-9]+:[0-9]+ remaining/) {
    split(substr($0, RSTART, RLENGTH - length(" remaining")), t, ":")
    if (t[1] + 0 == 0) printf "%dm", t[2] + 0
    else printf "%dh", t[1] + 0
    exit
  }')"

if [ -n "$left" ]; then
  sketchybar --set "$NAME" drawing=on label="$left"
else
  sketchybar --set "$NAME" drawing=off
fi
