#!/bin/sh

STATE="${TMPDIR:-/tmp}/sketchybar-network"

RED=0xfff7768e
FG=0xffffffff

iface="$(route -n get default 2>/dev/null | awk '/interface:/ { print $2; exit }')"

if [ -z "$iface" ]; then
  rm -f "$STATE"
  sketchybar --set "$NAME" drawing=on label.color="$RED" label="↑ ↓"
  exit 0
fi

counters="$(netstat -ib -I "$iface" 2>/dev/null \
              | awk '$3 ~ /^<Link/ { print $7, $10; exit }')"
[ -n "$counters" ] || exit 0

now="$(date +%s)"
previous="$(cat "$STATE" 2>/dev/null)"
printf '%s %s\n' "$now" "$counters" > "$STATE"

set -- $previous
[ "$#" -eq 3 ] || exit 0

label="$(awk -v t0="$1" -v i0="$2" -v o0="$3" -v t1="$now" -v c="$counters" '
  function human(rate) {
    if (rate >= 1048576) return sprintf("%dM", rate / 1048576)
    if (rate >= 1024)    return sprintf("%dK", rate / 1024)
    return sprintf("%dB", rate)
  }
  BEGIN {
    split(c, now_bytes, " ")
    dt = t1 - t0
    if (dt <= 0) exit 1

    down = (now_bytes[1] - i0) / dt
    up   = (now_bytes[2] - o0) / dt
    if (down < 0 || up < 0) exit 1

    out = ""
    if (up >= 1048576)   out = sprintf("↑ %s", human(up))
    if (down >= 1048576) out = out (out == "" ? "" : " ") sprintf("↓ %s", human(down))
    if (out == "") exit 1

    printf "%s", out
  }')"

if [ -n "$label" ]; then
  sketchybar --set "$NAME" drawing=on label.color="$FG" label="$label"
else
  sketchybar --set "$NAME" drawing=off
fi
