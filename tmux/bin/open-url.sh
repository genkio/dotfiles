#!/usr/bin/env bash
# Open a URL on the machine the tmux CLIENT is sitting at, or hand it to that
# machine's clipboard when no browser there can be reached. Prints "opened" or
# "copied" so the caller can word its own status message.
#
# Pick by where the client is, not by which opener happens to be installed.
# SSH_CONNECTION here is the session's (run-shell inherits session env, fed by
# update-environment on attach), so it means "this tmux server is remote" - not
# "some pane ssh'd out", which leaves the session env alone and still wants the
# local `open`. On a remote Mac `open` would put the tab on that machine's
# screen, and a remote xdg-open with no display can fall through to a text
# browser that fights for the pane.
set -euo pipefail

url=${1:?url required}
client_tty=${2:-}
client_termname=${3:-}

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

if [ -n "${SSH_CONNECTION:-}${SSH_TTY:-}" ]; then
  :
elif command -v open >/dev/null 2>&1; then
  open "$url" 2>/dev/null && { echo opened; exit 0; }
elif [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && command -v xdg-open >/dev/null 2>&1; then
  xdg-open "$url" >/dev/null 2>&1 && { echo opened; exit 0; }
fi

printf -- '%s' "$url" | "$here/osc52-copy.sh" "$client_tty" "$client_termname"
echo copied
