#!/usr/bin/env bash
set -euo pipefail

# Dump the macOS clipboard's image as PNG on stdout; exit 1 when the clipboard
# holds no image. Runs on whichever mac holds the clipboard: locally, or piped
# into `bash -s` over ssh by paste-image.sh on the machine you are ssh'd into.
# No heredoc anywhere, so it stays safe to feed on stdin: bash reads a piped
# script from the same stream a heredoc body would come from.

# Homebrew's bin is absent from the PATH of a non-interactive ssh session, so
# look there by hand or the ssh leg would always take the slow fallback.
for p in pngpaste /opt/homebrew/bin/pngpaste /usr/local/bin/pngpaste; do
  if command -v "$p" >/dev/null 2>&1; then
    exec "$p" -
  fi
done

# No pngpaste: AppleScript can coerce the clipboard to PNG but can only write to
# a file, never stdout, hence the temp file. A non-image clipboard fails the
# coercion inside the try, leaving the file empty (and the handle closed).
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
