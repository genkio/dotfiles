#!/bin/sh

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

battery=$(pmset -g batt 2>/dev/null | awk '
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
    if (pct + 0 < 20) printf "#[fg=red]%02d#[fg=#5c5c5c]", pct
    else printf "%02d", pct
    if (hours != "") {
      if (hours + 0 == 0) printf "/%dm", mins + 0
      else printf "/%d", hours
    }
    exit
  }
}')

if [ -n "$battery" ]; then
  printf "[%s/%s/%s]" "${cpu:-00}" "${ram:-00}" "$battery"
else
  printf "[%s/%s]" "${cpu:-00}" "${ram:-00}"
fi
