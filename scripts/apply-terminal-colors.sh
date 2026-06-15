#!/usr/bin/env bash
#
# Repaint the live terminal to the current theme via OSC 4/10/11/12 (colours
# from the matching kitty theme conf). Flips shell panes + padding too, not
# just apps that paint their own bg. Inside tmux it writes each client tty, so
# over SSH it reaches the client's kitty (one-way output, so tmux's colour
# cache is moot). Can't rewrite a remote client's config file, so a fresh window
# still starts from disk until the next local flip.
#   --print [light|dark]   dump the payload instead of writing

set -euo pipefail

mode="apply"
forced=""
for a in "$@"; do
  case "$a" in
    --print) mode="print" ;;
    light | dark) forced="$a" ;;
  esac
done

dotfiles="${DOTFILES_DIR:-$HOME/dotfiles}"
themes="$dotfiles/kitty/.config/kitty/themes"
theme="${forced:-$("$dotfiles/scripts/current-theme.sh")}"

if [ "$theme" = "dark" ]; then
  src="$themes/tokyonight-storm.conf"
else
  src="$themes/flexoki-light.conf"
fi
[ -f "$src" ] || exit 0

# kitty conf is "key #hexvalue" per line; map the few we need onto OSC.
osc="$(awk '
  $1 == "foreground" || $1 == "background" || $1 == "cursor" { c[$1] = $2 }
  $1 ~ /^color([0-9]|1[0-5])$/ { c[$1] = $2 }
  END {
    ESC = sprintf("%c", 27); BEL = sprintf("%c", 7)
    pal = ""
    for (i = 0; i < 16; i++) pal = pal sprintf("%d;%s;", i, c["color" i])
    sub(/;$/, "", pal)
    printf "%s]4;%s%s", ESC, pal, BEL
    printf "%s]10;%s%s", ESC, c["foreground"], BEL
    printf "%s]11;%s%s", ESC, c["background"], BEL
    printf "%s]12;%s%s", ESC, c["cursor"], BEL
  }
' "$src")"

if [ "$mode" = "print" ]; then
  printf '%s' "$osc"
  exit 0
fi

# tmux: every attached client tty. else: the controlling terminal.
if [ -n "${TMUX:-}" ] && command -v tmux > /dev/null 2>&1; then
  while IFS= read -r tty; do
    if [ -n "$tty" ] && [ -w "$tty" ]; then
      printf '%s' "$osc" > "$tty" 2> /dev/null || true
    fi
  done < <(tmux list-clients -F '#{client_tty}' 2> /dev/null | sort -u)
elif [ -w /dev/tty ]; then
  printf '%s' "$osc" > /dev/tty 2> /dev/null || true
fi
