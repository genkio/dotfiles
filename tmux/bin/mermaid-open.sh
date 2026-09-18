#!/usr/bin/env bash
set -euo pipefail

base="https://tools.simonwillison.net/grok-mermaid"

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

pane=${1:-}
[ -n "$pane" ] || pane=$(tmux display-message -p '#{pane_id}' 2>/dev/null || true)
client_tty=${2:-}
client_termname=${3:-}

say() { tmux display-message -t "$pane" "$1" 2>/dev/null || true; }

frag=$(LC_ALL=C awk '
  BEGIN {
    for (i = 0; i < 256; i++) ord[sprintf("%c", i)] = i
    safe = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*()" sprintf("%c", 39)
    indent = -1
  }
  { sub(/[ \t\r]+$/, "") }
  /^[ \t]*```/ { next }
  {
    line[++n] = $0
    if ($0 !~ /^[ \t]*$/) {
      match($0, /^[ \t]*/)
      if (indent < 0 || RLENGTH < indent) indent = RLENGTH
    }
  }
  END {
    if (indent < 0) exit 0
    first = 1; last = n
    while (first <= n && line[first] ~ /^[ \t]*$/) first++
    while (last >= first && line[last] ~ /^[ \t]*$/) last--
    for (i = first; i <= last; i++) {
      if (i > first) printf "%%0A"
      s = substr(line[i], indent + 1)
      for (j = 1; j <= length(s); j++) {
        c = substr(s, j, 1)
        if (index(safe, c)) printf "%s", c
        else printf "%%%02X", ord[c]
      }
    }
  }
' || true)

[ -n "$frag" ] || { say "mermaid: nothing selected"; exit 0; }

url="$base#$frag"

case "$("$here/open-url.sh" "$url" "$client_tty" "$client_termname")" in
  opened) say "mermaid: rendering in the browser" ;;
  copied) say "mermaid: no browser here, link copied - paste it locally" ;;
esac
