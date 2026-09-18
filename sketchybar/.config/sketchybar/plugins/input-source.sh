#!/bin/sh

id="$(osascript -l JavaScript -e '
  ObjC.import("Carbon");
  const source = $.TISCopyCurrentKeyboardInputSource();
  ObjC.castRefToObject(
    $.TISGetInputSourceProperty(source, $.kTISPropertyInputSourceID)
  ).js' 2>/dev/null)"

case "$id" in
  *Japanese.Romaji*) glyph="A" ;;
  *Japanese*)        glyph="あ" ;;
  *SCIM*|*TCIM*)     glyph="中" ;;
  *)                 glyph="A" ;;
esac

sketchybar --set "$NAME" label="$glyph"
