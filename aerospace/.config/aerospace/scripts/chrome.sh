#!/bin/sh

# The two things AeroSpace draws around windows but does not own: the sketchybar
# bar and the JankyBorders focus ring. A fullscreen window wants neither, and
# the ring's settings live here only, so fullscreen-toggle.sh can put them back.
#
# The argument is which displays should keep a bar: `all`, `none`, or the
# sketchybar display list to restrict it to. Hiding the ring means transparent
# colors rather than killing the process: borders has no disable verb, and a
# restart would lose every setting with it. The ring only ever draws around the
# focused window, which is the fullscreen one, so it goes globally.

PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

ring_off() {
  borders active_color=0x00000000 inactive_color=0x00000000
}

case "$1" in
  all)
    sketchybar --bar hidden=off display=all
    # Defaults are near-white on light themes, so the ring vanishes under
    # Flexoki Light. Orange reads on both; only the focused window is drawn.
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
