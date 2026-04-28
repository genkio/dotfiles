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

printf "[%s/%s]" "${cpu:-00}" "${ram:-00}"
