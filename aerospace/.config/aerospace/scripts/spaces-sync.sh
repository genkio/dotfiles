#!/bin/sh

PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

MEMO="${TMPDIR:-/tmp}/aerospace-spaces-state"

focused="$(aerospace list-workspaces --focused)"
occupied="$(
  { aerospace list-workspaces --monitor all --empty no
    aerospace list-workspaces --monitor all --visible
    printf '%s\n' "$focused"; } | sort -u
)"

attention=""

visible="$occupied"
[ "$(printf '%s\n' "$visible" | grep -c .)" -gt 1 ] || visible=""

visible="$(printf '%s' "$visible" | paste -sd, -)"
attention="$(printf '%s' "$attention" | paste -sd, -)"

apps="$(
  aerospace list-windows --all --format '%{workspace}|%{app-name}' | awk -F'|' '
    !seen[$1 "|" $2]++ {
      list[$1] = ($1 in list) ? list[$1] " \302\267 " $2 : $2
    }
    END { for (w in list) print w "\t" list[w] }
  ' | sort
)"

state="$focused|$visible|$attention|$apps"
if [ "$1" != force ] && [ "$(cat "$MEMO" 2>/dev/null)" = "$state" ]; then
  exit 0
fi

set -- aerospace_workspace_change \
       FOCUSED_WORKSPACE="$focused" \
       VISIBLE_WORKSPACES="$visible" \
       ATTENTION_WORKSPACES="$attention"

OLDIFS="$IFS"
IFS='
'
for line in $apps; do
  IFS="$OLDIFS"
  set -- "$@" "APPS_${line%%	*}=${line#*	}"
  IFS='
'
done
IFS="$OLDIFS"

sketchybar --trigger "$@"

printf '%s' "$state" > "$MEMO"
