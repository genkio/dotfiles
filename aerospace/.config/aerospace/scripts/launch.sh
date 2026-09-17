#!/bin/sh

# rcmd app keys. One monitor, or the app already has a window somewhere: plain
# open, which focuses it wherever it is. Otherwise Hammerspoon asks which
# monitor first (screen_picker.lua), so a cold launch does not land on whatever
# screen happened to have focus.

PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

app="$1"

if [ "$(aerospace list-monitors --count)" -le 1 ] ||
  aerospace list-windows --monitor all --format '%{app-name}' | grep -qxF "$app"; then
  exec open -a "$app"
fi

hs -c "require('screen_picker').pick([[$app]])" >/dev/null 2>&1 || exec open -a "$app"
