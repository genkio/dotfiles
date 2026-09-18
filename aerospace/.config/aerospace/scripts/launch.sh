#!/bin/sh

PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

app="$1"

if [ "$(aerospace list-monitors --count)" -le 1 ] ||
  aerospace list-windows --monitor all --format '%{app-name}' | grep -qxF "$app"; then
  exec open -a "$app"
fi

hs -c "require('screen_picker').pick([[$app]])" >/dev/null 2>&1 || exec open -a "$app"
