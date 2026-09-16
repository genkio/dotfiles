#!/bin/sh

# The current input source, shown as the script it types. There is no shell
# interface to it: this is the Carbon TIS call through JXA, reading the same ids
# hammerspoon/.hammerspoon/input_source.config.lua switches between per app.
#
# Kotoeri's romaji mode (英数) types latin, so it reads as A rather than あ -
# what the item answers is "what comes out when I type", not "which IME is
# loaded". Order matters below: romaji is a Japanese id too.

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
