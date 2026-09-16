#!/bin/sh

# $1 is this item's workspace id, baked into the script line in sketchybarrc.
# The event payload carries the workspaces worth showing, the focused one, and
# the ones where an agent is waiting on the user; spaces-sync.sh decides all
# three.

case ",$VISIBLE_WORKSPACES," in
  *",$1,"*) drawing=on ;;
  *)        drawing=off ;;
esac

# Red outranks focus: the point is to be findable from the other end of the
# desk. Filled, not outlined, and in the darker of the two palette reds, because
# the label stays white and white on the bright one is barely legible.
case ",$ATTENTION_WORKSPACES," in
  *",$1,"*)
    border=0xfff7768e
    fill=0xffaf3029
    ;;
  *)
    if [ "$1" = "$FOCUSED_WORKSPACE" ]; then
      border=0xffffffff
      fill=0x30ffffff
    else
      border=0x60ffffff
      fill=0x00000000
    fi
    ;;
esac

sketchybar --set "$NAME" \
           drawing="$drawing" \
           background.border_color="$border" \
           background.color="$fill"
