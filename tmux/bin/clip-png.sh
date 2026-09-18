#!/usr/bin/env bash
set -euo pipefail

for p in pngpaste /opt/homebrew/bin/pngpaste /usr/local/bin/pngpaste; do
  if command -v "$p" >/dev/null 2>&1; then
    exec "$p" -
  fi
done

tmp=$(mktemp -t clip-png)
trap 'rm -f "$tmp"' EXIT

osascript \
  -e "set fh to (open for access (POSIX file \"$tmp\") with write permission)" \
  -e "try" \
  -e "  set eof fh to 0" \
  -e "  write (the clipboard as «class PNGf») to fh" \
  -e "end try" \
  -e "close access fh" >/dev/null 2>&1 || exit 1

[ -s "$tmp" ] || exit 1
cat "$tmp"
