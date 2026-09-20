#!/bin/sh

PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

MEMO="${TMPDIR:-/tmp}/aerospace-spaces-state"
BADGE_MEMO="${TMPDIR:-/tmp}/aerospace-badges"
BADGE_TTL=6

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

windows="$(aerospace list-windows --all --format '%{workspace}|%{app-name}')"

now="$(date +%s)"
stamp="$(stat -f %m "$BADGE_MEMO" 2>/dev/null || echo 0)"
if [ "$((now - stamp))" -ge "$BADGE_TTL" ]; then
  badges=""

  if printf '%s\n' "$windows" | grep -q '|Mail$'; then
    unread="$(osascript -e 'with timeout of 3 seconds
      tell application "Mail" to get unread count of inbox
    end timeout' 2>/dev/null)"
    case "$unread" in
      "" | 0) ;;
      *) badges="Mail=$unread" ;;
    esac
  fi

  printf '%s' "$badges" > "$BADGE_MEMO"
else
  badges="$(cat "$BADGE_MEMO" 2>/dev/null)"
fi

apps="$(
  printf '%s\n' "$windows" | awk -F'|' -v badges="$badges" '
    BEGIN {
      n = split(badges, lines, "\t")
      for (i = 1; i <= n; i++) {
        p = index(lines[i], "=")
        if (p > 1) badge[substr(lines[i], 1, p - 1)] = substr(lines[i], p + 1)
      }
    }
    !seen[$1 "|" $2]++ {
      name = ($2 in badge) ? $2 " (" badge[$2] ")" : $2
      list[$1] = ($1 in list) ? list[$1] " \302\267 " name : name
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
