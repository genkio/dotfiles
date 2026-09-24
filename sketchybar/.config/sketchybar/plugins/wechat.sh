#!/bin/sh

# WeChat has no AppleScript dictionary; read the Dock badge it publishes to Launch Services.
badge="$(lsappinfo info -app com.tencent.xinWeChat -long 2>/dev/null |
  sed -n 's/.*"StatusLabel"={ "label"="\([^"]*\)".*/\1/p')"

if [ -n "$badge" ]; then
  sketchybar --set "$NAME" drawing=on label="WeChat ($badge)"
else
  sketchybar --set "$NAME" drawing=off
fi
