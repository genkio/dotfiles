#!/usr/bin/env bash
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
