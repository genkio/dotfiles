#!/bin/sh
#
# The left status block, by exception: it prints nothing at all while the
# machine is healthy, and only names the signals that need a look. Fields are
# joined with "/" inside one pair of brackets, e.g. [c91/r94/b85/5h/net/dbx]:
#
#   c<pct>  cpu is pegged            r<pct>  ram is pegged
#   net     no route to the internet  dbx     dropbox syncing or wedged
#   b<pct>/<left>  running on battery
#
# 4th arg "all" is the prefix+S override: print every field whatever its value,
# healthy ones muted, so the bar can be inspected instead of only warned by.
#
# hex from apply-theme so tinted segments track the active theme, not fixed values
muted="${1:-5c5c5c}"
red="${2:-af3029}"
yellow="${3:-ad8301}"
show_all="${4:-}"
bin_dir="${0%/*}"

# Thresholds are asymmetric on purpose: a field appears at *_HIGH and only goes
# away again below *_CLEAR, so a load hovering on the line doesn't blink the
# whole block in and out every status-interval. macOS parks a healthy machine
# around 70-80% ram (inactive pages it will hand back on demand), so 90 is the
# first number that actually means pressure.
cpu_high=85
cpu_clear=70
ram_high=90
ram_clear=85
# cpu must read high twice running before it shows: a single 15s sample catches
# every compile and video decode, and those are not news.
cpu_hits_needed=2

state_dir="${XDG_CACHE_HOME:-$HOME/.cache}"
state_file="$state_dir/tmux-status-usage.state"

# top -l 2: first sample is a since-boot average, only the second is instantaneous.
cpu=$(top -l 2 -n 0 2>/dev/null | awk '
/CPU usage/ {
  gsub("%", "", $3)
  gsub("%", "", $5)
  used = $3 + $5
}
END { printf "%02.0f", used }')

# memory_pressure's "free %" counts reclaimable pages as free, reading ~half of
# real usage; compute from vm_stat to match Activity Monitor / htop.
ram=$(vm_stat 2>/dev/null | awk -v total_bytes="$(sysctl -n hw.memsize 2>/dev/null)" '
/page size of/      { ps = $8 }
/Pages free/        { gsub("\\.", "", $3); free  = $3 }
/Pages inactive/    { gsub("\\.", "", $3); inact = $3 }
/Pages speculative/ { gsub("\\.", "", $3); spec  = $3 }
/Pages purgeable/   { gsub("\\.", "", $3); purg  = $3 }
END {
  if (ps == 0 || total_bytes == "") exit
  avail = (free + inact + spec + purg) * ps
  printf "%02.0f", 100 - (100 * avail / total_bytes)
}')

# carried across runs: which fields are currently latched on, and how many
# consecutive high cpu samples we have seen.
cpu_shown=""
ram_shown=""
cpu_hits=""
[ -r "$state_file" ] && read -r cpu_shown ram_shown cpu_hits < "$state_file" 2>/dev/null
# a truncated or hand-edited state file must not wedge the block on
case "$cpu_shown" in 0|1) ;; *) cpu_shown=0 ;; esac
case "$ram_shown" in 0|1) ;; *) ram_shown=0 ;; esac
case "$cpu_hits" in ""|*[!0-9]*) cpu_hits=0 ;; esac

if [ -n "$cpu" ] && [ "$cpu" -ge "$cpu_high" ] 2>/dev/null; then
  cpu_hits=$((cpu_hits + 1))
  [ "$cpu_hits" -ge "$cpu_hits_needed" ] && cpu_shown=1
else
  cpu_hits=0
  [ -n "$cpu" ] && [ "$cpu" -lt "$cpu_clear" ] 2>/dev/null && cpu_shown=0
fi

if [ -n "$ram" ] && [ "$ram" -ge "$ram_high" ] 2>/dev/null; then
  ram_shown=1
elif [ -n "$ram" ] && [ "$ram" -lt "$ram_clear" ] 2>/dev/null; then
  ram_shown=0
fi

mkdir -p "$state_dir" 2>/dev/null
printf '%s %s %s\n' "$cpu_shown" "$ram_shown" "$cpu_hits" > "$state_file" 2>/dev/null

# override AFTER the state write, so a spell in show-all mode doesn't teach the
# latch that cpu/ram were high and leave them stuck on when it ends.
cpu_latched="$cpu_shown"
ram_latched="$ram_shown"
if [ "$show_all" = all ]; then
  cpu_shown=1
  ram_shown=1
fi

# scutil reachability = routing path, no packets, fast. not a real internet probe.
case "$(scutil -r 8.8.8.8 2>/dev/null)" in
  Reachable*) net_down=0 ;;
  *)          net_down=1 ;;
esac

dbx=$("$bin_dir/maestral-state.sh" 2>/dev/null)

# Battery only exists as a field while unplugged; on AC there is nothing to say.
# In show-all mode the charge prints on AC too, but without the time left: pmset
# reports "0:00 remaining" while charged, which would read as a dead battery.
battery=$(pmset -g batt 2>/dev/null | awk -v muted="$muted" -v red="$red" -v all="$show_all" '
NR == 1 && /Battery Power/ { on_battery = 1 }
NR == 1 && all == "all" { show = 1 }
NR > 1 && (on_battery || show) {
  if (match($0, /[0-9]+%/)) {
    pct = substr($0, RSTART, RLENGTH - 1)
  }
  if (match($0, /[0-9]+:[0-9]+ remaining/)) {
    tm = substr($0, RSTART, RLENGTH - length(" remaining"))
    split(tm, parts, ":")
    hours = parts[1]
    mins = parts[2]
  }
  if (pct != "") {
    if (pct + 0 < 20) printf "#[fg=#%s]b%02d#[fg=#%s]", red, pct, muted
    else printf "b%02d", pct
    if (hours != "" && on_battery) {
      if (hours + 0 == 0) printf "/%dm", mins + 0
      else printf "/%dh", hours + 0
    }
    exit
  }
}')

fields=""
add() { [ -n "$fields" ] && fields="$fields/$1" || fields="$1"; }

# a field the latch put on is always worth a colour, even mid-decay; one that
# only shows because of prefix+S stays muted until it crosses its own threshold.
tint_for() { # value red_at high_at latched
  if [ "$1" -ge "$2" ] 2>/dev/null; then printf '%s' "$red"
  elif [ "$4" = 1 ] || [ "$1" -ge "$3" ] 2>/dev/null; then printf '%s' "$yellow"
  else printf '%s' "$muted"
  fi
}

if [ "$cpu_shown" = 1 ] && [ -n "$cpu" ]; then
  tint=$(tint_for "$cpu" 95 "$cpu_high" "$cpu_latched")
  add "#[fg=#$tint]c$cpu#[fg=#$muted]"
fi
if [ "$ram_shown" = 1 ] && [ -n "$ram" ]; then
  tint=$(tint_for "$ram" 96 "$ram_high" "$ram_latched")
  add "#[fg=#$tint]r$ram#[fg=#$muted]"
fi
# battery sits with cpu/ram: the numeric fields read as one group, the word
# fields (net/dbx) as another.
[ -n "$battery" ] && add "$battery"

if [ "$net_down" = 1 ]; then
  add "#[fg=#$red]net#[fg=#$muted]"
elif [ "$show_all" = all ]; then
  add "net"
fi
case "$dbx" in
  error) add "#[fg=#$red]dbx#[fg=#$muted]" ;;
  sync)  add "#[fg=#$yellow]dbx#[fg=#$muted]" ;;
  *)     [ "$show_all" = all ] && add "dbx" ;;
esac

[ -n "$fields" ] && printf '[%s]' "$fields"
