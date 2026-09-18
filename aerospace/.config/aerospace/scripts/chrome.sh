#!/bin/sh

PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

ring_off() {
  borders active_color=0x00000000 inactive_color=0x00000000
}

case "$1" in
  all)
    sketchybar --bar hidden=off display=all
    borders active_color=0xffda702c inactive_color=0x00000000 width=6.0 hidpi=on
    ;;
  none)
    sketchybar --bar hidden=on
    ring_off
    ;;
  *)
    sketchybar --bar hidden=off display="$1"
    ring_off
    ;;
esac
