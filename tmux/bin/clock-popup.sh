#!/usr/bin/env bash
#
# prefix + T: the "when am I" panel. Replaces the [%H:%M] that used to sit in
# status-right - the time is worth a keystroke, not eight permanent columns.
# Ticks once a second; q / Escape / Enter closes it.
#
# macOS ships bash 3.2, so no printf %()T and no read -N here.

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

# Redraw over the previous frame instead of clearing: a clear + rewrite every
# second flickers, and every line here is a fixed width.
printf '\033[?25l\033[2J'
trap 'printf "\033[?25h\033[2J\033[H"' EXIT

year=$(date +%Y)
year_days=$(date -j -f "%Y-%m-%d" "$year-12-31" "+%j" 2>/dev/null)

# kern.boottime, not `uptime`: uptime's remainder-after-days is bare H:MM
# ("up 6 days, 6:09"), which reads as a clock time two lines under an actual
# clock. Its text also has several shapes to parse - "up 3 mins", "up 1:05",
# "up 1 day, 0:05" - so do the arithmetic and pick the units explicitly.
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

# every line ends in ESC[K: "6d 6h 9m" -> "6d 6h 10m" changes width, and without
# the erase the old tail stays on screen under the new frame
eol="${esc}[K"

# One left margin for the whole panel, and the day grid's column stride. cal's
# native pitch of 3 leaves the calendar cramped against the text above it; 5
# puts text_w at 32, so indent + grid spans 34 and the calendar ends flush with
# the week/day/uptime line, the widest thing here. Both need the popup's 36
# inner columns (-w 38), and that line is what sets the width: it reaches 36 once
# uptime hits three-digit days. Change -w and this together.
indent='  '
pitch=5
text_w=$((7 * 2 + 6 * (pitch - 2)))

# Columns a plain string occupies. ${#s} counts bytes, not characters, whenever
# the locale isn't UTF-8 - an SSH session that forwards no locale lands in C -
# and the middot separator is two bytes there, which would shift the centering.
# Fold it to one byte first and the count is right under either locale. Setting
# LC_CTYPE here would not do it: LC_ALL overrides LC_CTYPE.
width() {
  local plain=${1//·/.}
  echo "${#plain}"
}

# Leading whitespace that centers a string of visible width $1 over text_w. The
# rows carry color escapes, which are zero-width but would count toward ${#s},
# so the caller measures the plain text and this only emits the margin.
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
  # cal -h: its own today-highlight needs a standout-capable TERM and quietly
  # does nothing under tmux-256color, so mark today here instead, in the accent.
  # cal always emits 8 lines, padding short months, so dropping the trailing
  # blank leaves a fixed 7 and the popup height never has to guess.
  #
  # cal lays days out 2 chars wide on a 3-char pitch, 22 columns total, which
  # leaves the calendar visibly narrower than the text above it. Re-space to
  # PITCH so the grid spans TEXT_W and the whole panel shares one right edge.
  # Reading cells by offset and re-emitting also means the escapes splice in at
  # a known place, rather than being re-joined from fields and hoping.
  cal -h | sed '$d' | awk -v today="$(date +%d)" -v on="$(sgr "$accent")$(printf '\033[1m')" \
                          -v off="$reset" -v eol="$eol" \
                          -v indent="$indent" -v pitch="$pitch" '
    function pad(n,   s) { s = ""; while (n-- > 0) s = s " "; return s }
    # cal line 1 is the month and year, which the date row above already states
    NR == 1 { next }
    {
      out = ""
      for (i = 0; i < 7; i++) {
        cell = substr($0, 3 * i + 1, 2)
        day = cell; gsub(/ /, "", day)
        # row 2 is Su..Sa, never a date, so it re-spaces without the highlight
        if (NR > 2 && day != "" && day + 0 == today + 0) out = out on cell off
        else out = out cell
        if (i < 6) out = out pad(pitch - 2)
      }
      print indent out eol
    }'
}

while :; do
  render
  # -t 1 is the tick; a keypress that isn't an exit key just redraws early
  if IFS= read -r -s -n 1 -t 1 key; then
    case "$key" in
      q|Q|"$esc"|"") break ;;
    esac
  fi
done
