#!/bin/sh

# hex from apply-theme so tinted segments track the active theme, not fixed values
muted="${1:-5c5c5c}"
red="${2:-af3029}"
yellow="${3:-ad8301}"
bin_dir="${0%/*}"

cpu=$(top -l 1 -n 0 2>/dev/null | awk '
/CPU usage/ {
  gsub("%", "", $3)
  gsub("%", "", $5)
  printf "%02.0f", $3 + $5
  exit
}')

ram=$(memory_pressure 2>/dev/null | awk -F': ' '
/System-wide memory free percentage/ {
  gsub("%", "", $2)
  printf "%02.0f", 100 - $2
  exit
}')

battery=$(pmset -g batt 2>/dev/null | awk -v muted="$muted" '
NR == 1 && /Battery Power/ { on_battery = 1 }
NR > 1 && on_battery {
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
    if (pct + 0 < 20) printf "#[fg=red]%02d#[fg=#%s]", pct, muted
    else printf "%02d", pct
    if (hours != "") {
      if (hours + 0 == 0) printf "/%dm", mins + 0
      else printf "/%d", hours
    }
    exit
  }
}')

# scutil reachability = routing path, no packets, fast. not a real internet probe.
net=$(scutil -r 8.8.8.8 2>/dev/null)
case "$net" in
  Reachable*) cpu_open=""; cpu_close="" ;;
  *)          cpu_open="#[fg=red]"; cpu_close="#[fg=#$muted]" ;;
esac

# ram carries the maestral (dropbox) sync tint, keeping every left-block signal here.
ram_open="$("$bin_dir/maestral-color.sh" "$red" "$yellow" 2>/dev/null)"
[ -n "$ram_open" ] && ram_close="#[fg=#$muted]" || ram_close=""

if [ -n "$battery" ]; then
  printf "[%s%s%s/%s%s%s/%s]" "$cpu_open" "${cpu:-00}" "$cpu_close" "$ram_open" "${ram:-00}" "$ram_close" "$battery"
else
  printf "[%s%s%s/%s%s%s]" "$cpu_open" "${cpu:-00}" "$cpu_close" "$ram_open" "${ram:-00}" "$ram_close"
fi
