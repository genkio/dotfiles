#!/usr/bin/env bash
set -euo pipefail

# tmux copy-mode yanks screen rows, so prose that a TUI soft-wrapped arrives as
# hard newlines plus the TUI's left padding. Rejoin it into one line.
exec awk '
  { gsub(/^[ \t]+/, ""); gsub(/[ \t]+$/, "") }
  !NF { next }
  { printf "%s%s", sep, $0; sep = " " }
'
