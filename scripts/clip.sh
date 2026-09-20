#!/usr/bin/env bash
set -uo pipefail

VIEWER_BASE=52528
VIEWER_SLOTS=8

TMP="$(mktemp -t clip)"
trap 'rm -f "$TMP"' EXIT

if [[ $# -gt 0 ]]; then
  printf '%s' "$*" >"$TMP"
else
  cat >"$TMP"
fi

[[ -s "$TMP" ]] || exit 0

copied=0

for ((port = VIEWER_BASE; port < VIEWER_BASE + VIEWER_SLOTS; port++)); do
  if { cat "$TMP" >"/dev/tcp/127.0.0.1/$port"; } 2>/dev/null; then
    copied=1
  fi
done

if command -v pbcopy >/dev/null 2>&1; then
  pbcopy <"$TMP" && copied=1
elif command -v wl-copy >/dev/null 2>&1; then
  wl-copy <"$TMP" && copied=1
elif command -v xclip >/dev/null 2>&1; then
  xclip -selection clipboard <"$TMP" && copied=1
fi

if [[ "$copied" -eq 0 || -n "${SSH_CONNECTION:-}" ]]; then
  if { : >/dev/tty; } 2>/dev/null; then
    printf '\033]52;c;%s\a' "$(base64 <"$TMP" | tr -d '\r\n')" >/dev/tty && copied=1
  fi
fi

[[ "$copied" -eq 1 ]]
