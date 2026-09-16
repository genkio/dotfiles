#!/bin/sh

# Throughput on the default route, from the cumulative byte counters netstat
# keeps per interface. Each tick is a fresh process, so the previous sample goes
# to $TMPDIR and the rate is the delta between the two over the time between
# them - there is no interface-level "current speed" to read.
#
# Three states, and two of them say something worth a glance: bare red arrows
# when there is no route at all, the rates once either direction reaches a
# megabyte a second, and nothing whatsoever in between. A meter that is always
# on is a meter nobody reads.

STATE="${TMPDIR:-/tmp}/sketchybar-network"

# The dark half of the tmux palette (apply-theme.sh), since this bar is dark
# whatever the terminal theme is doing.
RED=0xfff7768e
FG=0xffffffff

iface="$(route -n get default 2>/dev/null | awk '/interface:/ { print $2; exit }')"

# No default route. This is the cheap test: it catches wifi off, no lease and
# no route, but not a captive portal or dead DNS, which would need a probe on
# every tick.
if [ -z "$iface" ]; then
  rm -f "$STATE"
  sketchybar --set "$NAME" drawing=on label.color="$RED" label="↑ ↓"
  exit 0
fi

# The Link row is the one carrying byte counters; per-address rows repeat the
# same totals with the columns shifted.
counters="$(netstat -ib -I "$iface" 2>/dev/null \
              | awk '$3 ~ /^<Link/ { print $7, $10; exit }')"
[ -n "$counters" ] || exit 0

now="$(date +%s)"
previous="$(cat "$STATE" 2>/dev/null)"
printf '%s %s\n' "$now" "$counters" > "$STATE"

# First tick after a boot, a reconnect or a link change has nothing to diff.
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
    # Counters restart when the interface does; report nothing rather than a
    # spike of nonsense.
    if (down < 0 || up < 0) exit 1

    # Each direction earns its own place. A direction sitting at a few hundred
    # kilobytes is the normal state of a machine that is on a network, and
    # printing it next to a real transfer only makes the real one harder to read.
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
