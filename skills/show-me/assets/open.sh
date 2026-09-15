#!/usr/bin/env zsh
# Usage: open.sh path/to/show-me-x.html  -> ensures the notes server runs, opens the page through it.
set -eu
port="${SHOW_ME_PORT:-4747}"
here="$(cd "$(dirname "$0")" && pwd -P)"
file="$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")"
if ! curl -sf "http://127.0.0.1:${port}/_show-me/health" >/dev/null 2>&1; then
  nohup node "${here}/serve.mjs" >/tmp/show-me-serve.log 2>&1 &
  disown
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    curl -sf "http://127.0.0.1:${port}/_show-me/health" >/dev/null 2>&1 && break
    sleep 0.2
  done
fi
url="http://127.0.0.1:${port}${file}"
echo "$url"
open "$url"
