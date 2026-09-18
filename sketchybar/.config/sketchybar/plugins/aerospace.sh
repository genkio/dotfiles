#!/bin/sh

case ",$VISIBLE_WORKSPACES," in
  *",$1,"*) drawing=on ;;
  *)        drawing=off ;;
esac

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
