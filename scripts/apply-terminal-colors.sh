#!/usr/bin/env bash

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
themes="$dotfiles/alacritty/.config/alacritty/themes"
theme="${forced:-$("$dotfiles/scripts/current-theme.sh")}"

if [ "$theme" = "dark" ]; then
  src="$themes/tokyonight-storm.toml"
else
  src="$themes/flexoki-light.toml"
fi
[ -f "$src" ] || exit 0

osc="$(awk '
  /^\[colors\./ { sec = $0; gsub(/[][ \t]/, "", sec); next }
  /=[ \t]*"#[0-9a-fA-F]+"/ {
    eq = index($0, "=")
    key = substr($0, 1, eq - 1); gsub(/[ \t]/, "", key)
    rest = substr($0, eq + 1)
    q = index(rest, "\""); rest = substr(rest, q + 1)
    q = index(rest, "\""); val = substr(rest, 1, q - 1)
    c[sec "." key] = val
  }
  END {
    ESC = sprintf("%c", 27); BEL = sprintf("%c", 7)
    split("black red green yellow blue magenta cyan white", n, " ")
    pal = ""
    for (i = 1; i <= 8; i++) pal = pal sprintf("%d;%s;", i - 1, c["colors.normal." n[i]])
    for (i = 1; i <= 8; i++) pal = pal sprintf("%d;%s;", i + 7, c["colors.bright." n[i]])
    sub(/;$/, "", pal)
    printf "%s]4;%s%s", ESC, pal, BEL
    printf "%s]10;%s%s", ESC, c["colors.primary.foreground"], BEL
    printf "%s]11;%s%s", ESC, c["colors.primary.background"], BEL
    printf "%s]12;%s%s", ESC, c["colors.cursor.cursor"], BEL
  }
' "$src")"

if [ "$mode" = "print" ]; then
  printf '%s' "$osc"
  exit 0
fi

if command -v tmux > /dev/null 2>&1 && tmux info > /dev/null 2>&1; then
  while IFS= read -r tty; do
    if [ -n "$tty" ] && [ -w "$tty" ]; then
      printf '%s' "$osc" > "$tty" 2> /dev/null || true
    fi
  done < <(tmux list-clients 2> /dev/null | sed -n 's/^\([^:]*\):.*/\1/p' | sort -u)
fi

if [ -z "${TMUX:-}" ] && [ -w /dev/tty ]; then
  printf '%s' "$osc" > /dev/tty 2> /dev/null || true
fi
