#!/usr/bin/env bash

set -uo pipefail

theme="$("${DOTFILES_DIR:-$HOME/dotfiles}/scripts/current-theme.sh" 2>/dev/null || echo light)"
if [ "$theme" = "dark" ]; then
  fg='192;202;245'; muted='86;95;137'; accent='122;162;247'
else
  fg='16;15;15';    muted='135;133;128'; accent='32;94;166'
fi

sgr()   { printf '\033[38;2;%sm' "$1"; }
reset=$'\033[0m'
esc=$'\033'

printf '\033[?25l\033[2J'
trap 'printf "\033[?25h\033[2J\033[H"' EXIT

year=$(date +%Y)
year_days=$(date -j -f "%Y-%m-%d" "$year-12-31" "+%j" 2>/dev/null)

boot_epoch=$(sysctl -n kern.boottime 2>/dev/null | awk '{ gsub(",", "", $4); print $4 }')

uptime_str() {
  local now secs d h m
  case "$boot_epoch" in
    ""|*[!0-9]*) echo "unknown"; return ;;
  esac
  now=$(date +%s)
  secs=$((now - boot_epoch))
  d=$((secs / 86400))
  h=$(((secs % 86400) / 3600))
  m=$(((secs % 3600) / 60))
  if [ "$d" -gt 0 ]; then printf '%dd %dh %dm' "$d" "$h" "$m"
  elif [ "$h" -gt 0 ]; then printf '%dh %dm' "$h" "$m"
  else printf '%dm' "$m"
  fi
}

eol="${esc}[K"

indent='  '
pitch=5
text_w=$((7 * 2 + 6 * (pitch - 2)))

width() {
  local plain=${1//·/.}
  echo "${#plain}"
}

lead() {
  local n=$(((text_w - $1) / 2))
  [ "$n" -lt 0 ] && n=0
  printf '%*s' "$((${#indent} + n))" ''
}

render() {
  local day_line clock_line utc info

  printf '\033[H'
  printf '%s\n' "$eol"

  day_line=$(date '+%A %d %B %Y')
  printf '%s%s%s%s%s\n' "$(lead ${#day_line})" \
    "$(sgr "$fg")" "$day_line" "$reset" "$eol"

  clock_line=$(date '+%H:%M:%S %Z')
  utc=$(date -u '+%H:%M')
  printf '%s%s%s%s  %sUTC %s%s%s\n' "$(lead $((${#clock_line} + 6 + ${#utc})))" \
    "$(sgr "$accent")" "$clock_line" "$reset" \
    "$(sgr "$muted")" "$utc" "$reset" "$eol"

  printf '%s\n' "$eol"

  info="week $(date +%V) · day $(date +%j) · up $(uptime_str)"
  printf '%s%s%s%s%s\n' "$(lead "$(width "$info")")" \
    "$(sgr "$muted")" "$info" "$reset" "$eol"

  printf '%s\n' "$eol"
  cal -h | sed '$d' | awk -v today="$(date +%d)" -v on="$(sgr "$accent")$(printf '\033[1m')" \
                          -v off="$reset" -v eol="$eol" \
                          -v indent="$indent" -v pitch="$pitch" '
    function pad(n,   s) { s = ""; while (n-- > 0) s = s " "; return s }
    NR == 1 { next }
    {
      out = ""
      for (i = 0; i < 7; i++) {
        cell = substr($0, 3 * i + 1, 2)
        day = cell; gsub(/ /, "", day)
        if (NR > 2 && day != "" && day + 0 == today + 0) out = out on cell off
        else out = out cell
        if (i < 6) out = out pad(pitch - 2)
      }
      print indent out eol
    }'
}

while :; do
  render
  if IFS= read -r -s -n 1 -t 1 key; then
    case "$key" in
      q|Q|"$esc"|"") break ;;
    esac
  fi
done
