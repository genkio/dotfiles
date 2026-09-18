#!/usr/bin/env bash
set -euo pipefail

exec awk '
  { gsub(/^[ \t]+/, ""); gsub(/[ \t]+$/, "") }
  !NF { next }
  { printf "%s%s", sep, $0; sep = " " }
'
