#!/usr/bin/env bash
set -euo pipefail

self=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
trap 'tmux display-message "window-chooser: failed at line $LINENO"' ERR
us=$'\x1f'

pane_tail() {
  tmux capture-pane -e -p -t "$1" \
    | sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}' \
    | awk '
        { line[NR] = $0; plain = $0; gsub(/\033\[[0-9;]*m/, "", plain); text[NR] = plain }
        END {
          end = NR
          for (i = NR; i > NR - 12 && i > 1; i--) {
            if (text[i] !~ /^[[:space:]]*❯/) continue
            for (j = i - 1; j >= 1 && j >= i - 8 && text[j] !~ /^[[:space:]]*$/; j--) ;
            end = j
            break
          }
          while (end > 0 && text[end] ~ /^[[:space:]]*$/) end--
          for (i = 1; i <= end; i++) print line[i]
        }' \
    | reflow "$3" \
    | tail_rows "$2" "$4"
}

tail_rows() {
  awk -v budget="$1" -v cols="$2" '
    { line[NR] = $0; plain = $0; gsub(/\033\[[0-9;]*m/, "", plain); need[NR] = int((length(plain) - 1) / cols) + 1 }
    END {
      for (i = NR; i >= 1 && budget >= need[i]; i--) budget -= need[i]
      for (i++; i <= NR; i++) print line[i]
    }'
}

reflow() {
  awk -v w="$1" '
    function strip_lead(s,   c, seg) {
      c = ""
      while (match(s, /^(\033\[[0-9;]*m|[[:space:]])/)) {
        seg = substr(s, 1, RLENGTH)
        if (seg ~ /^\033/) c = c seg
        s = substr(s, RLENGTH + 1)
      }
      return c s
    }
    function strip_trail(s,   c, seg) {
      c = ""
      while (match(s, /(\033\[[0-9;]*m|[[:space:]])$/)) {
        seg = substr(s, RSTART)
        if (seg ~ /^\033/) c = seg c
        s = substr(s, 1, RSTART - 1)
      }
      return s c
    }
    function continues(n) {
      if (n !~ /^[[:space:]]+[^[:space:]]/) return 0
      if (n ~ /^[[:space:]]*(⎿|●|○|◦|✻|✶|✽|✢|✳|✷|·|─|❯|•|\*|-|\||[0-9]+\.)[[:space:]]/) return 0
      return 1
    }
    { line[NR] = $0; plain = $0; gsub(/\033\[[0-9;]*m/, "", plain); text[NR] = plain }
    END {
      i = 1
      while (i <= NR) {
        cur = line[i]; curp = text[i]
        while (i < NR && length(curp) >= w - 16 && continues(text[i+1])) {
          i++
          nxt = text[i]; sub(/^[[:space:]]+/, "", nxt)
          sub(/[[:space:]]+$/, "", curp)
          cur = strip_trail(cur) " " strip_lead(line[i]); curp = curp " " nxt
        }
        print cur; i++
      }
    }'
}

pane_list() {
  tmux list-panes -t "$1" -F \
    "#{pane_id}$us#{pane_index}$us#{pane_width}$us#{@agent_pane_state}$us#{pane_active}$us#{pane_current_command}$us#{?#{!=:#{pane_title},#{host_short}},#{pane_title},}"
}

selected_row() {
  local win=$1 panes=$2 sw row
  read -r sw row < "$WC_STATE" 2>/dev/null || true
  if [[ $sw == "$win" && -n $row ]]; then printf '%s\n' "$row"; return; fi
  printf '%s\n' "$panes" | awk -F"$us" '$5==1{print NR; exit}'
}

move_pane() {
  local delta=$1 win=$2 panes n row
  panes=$(pane_list "$win")
  n=$(printf '%s\n' "$panes" | wc -l | tr -d ' ')
  row=$(selected_row "$win" "$panes")
  row=$(( (row - 1 + delta + n) % n + 1 ))
  printf '%s %s\n' "$win" "$row" > "$WC_STATE"
}

selected_pane() {
  local win=$1 panes
  panes=$(pane_list "$win")
  printf '%s\n' "$panes" | awk -F"$us" -v r="$(selected_row "$win" "$panes")" 'NR==r{print $1}'
}

preview() {
  local win=$1 rows=${FZF_PREVIEW_LINES:-40} cols=${FZF_PREVIEW_COLUMNS:-80}
  local panes n per id idx width state active cmd title head colour sel row=0
  panes=$(pane_list "$win")
  n=$(printf '%s\n' "$panes" | wc -l | tr -d ' ')
  sel=$(selected_row "$win" "$panes")
  per=$(( (rows - 2 * n + 1) / n ))
  (( per < 3 )) && per=3
  local first=1
  while IFS=$us read -r id idx width state active cmd title; do
    (( first )) && first=0 || echo
    row=$(( row + 1 ))
    case $state in
      attention) colour='1;7;31' ;;
      busy)      colour='1;7;33' ;;
      awaiting)  colour='1;7;32' ;;
      *)         colour='1;7' ;;
    esac
    if (( row == sel )); then head=" ▶ $idx · $cmd${title:+ · $title}"; else colour="$colour;2"; head="   $idx · $cmd${title:+ · $title}"; fi
    head=${head:0:cols-2}
    printf '\e[%sm%s%*s\e[0m\n' "$colour" "$head" $(( cols - ${#head} - 2 )) ''
    pane_tail "$id" "$per" "$width" "$cols"
  done <<<"$panes"
}

refresh_loop() {
  ( while curl -s -XPOST "localhost:$FZF_PORT" -d refresh-preview >/dev/null 2>&1; do
      h=$(tmux display -p -c "$WC_CLIENT" '#{client_height}' 2>/dev/null)
      if [[ -n $h && $h != "$WC_H0" ]]; then
        curl -s -XPOST "localhost:$FZF_PORT" -d "become(printf 'RESIZE\\t%s\\n' {1})" >/dev/null 2>&1
        break
      fi
      sleep 1
    done ) >/dev/null 2>&1 </dev/null &
}

window_rows() {
  local scope=() label id st active label
  if [[ $all == 1 ]]; then
    scope=(-a)
    label='#{session_name}:#{window_index} #{window_name}#{window_flags}'
  else
    scope=(-t "$session")
    label='#{window_index}: #{window_name}#{window_flags}'
  fi
  tmux list-windows "${scope[@]}" -F \
    "#{window_id}$us#{?@agent_attention,a,#{?@agent_busy,b,#{?@agent_awaiting,w,}}}$us#{?#{&&:#{window_active},#{==:#{session_id},$sid}},1,0}$us$label" \
  | while IFS=$us read -r id st active label; do
      case $st in
        a) dot=$'\e[1;31m●\e[0m' ;;
        b) dot=$'\e[1;33m●\e[0m' ;;
        w) dot=$'\e[1;32m●\e[0m' ;;
        *) dot=' ' ;;
      esac
      printf '%s\t%s\t%s %s\n' "$id" "$active" "$dot" "$label"
    done
}

case ${1:-} in
  --preview) preview "$2"; exit 0 ;;
  --pane) move_pane "$2" "$3"; exit 0 ;;
  --refresh) refresh_loop; exit 0 ;;
esac

all=0 select=
[[ ${1:-} == --all ]] && { all=1; shift; }
if [[ ${1:-} == --select ]]; then select=$2; shift 2; fi
client=${2:-$(tmux display -p '#{client_name}')}
session=${1:-$(tmux display -p -c "$client" '#{session_id}')}
sid=$(tmux display -p -t "$session" '#{session_id}')
export WC_CLIENT=$client
WC_STATE=$(mktemp); export WC_STATE
trap 'rm -f "$WC_STATE"' EXIT
WC_H0=$(tmux display -p -c "$client" '#{client_height}'); export WC_H0

list=$(window_rows)
n=$(printf '%s\n' "$list" | wc -l | tr -d ' ')
cur=$(printf '%s\n' "$list" | awk -F'\t' -v sel="$select" '(sel != "" && $1 == sel) || (sel == "" && $2 == 1) {print NR; exit}')
rows=$(stty size </dev/tty 2>/dev/null | cut -d' ' -f1)
psize=$(( ${rows:-50} - n - 2 ))
(( psize < 10 )) && psize=10

pick=$(printf '%s\n' "$list" | fzf --ansi --layout=reverse --no-input --info=hidden \
  --delimiter '\t' --with-nth 3.. --no-sort --cycle --pointer '▶' --prompt 'search> ' \
  --preview "$self --preview {1}" \
  --preview-window "down,$psize,border-top,wrap" \
  --listen-unsafe 0 \
  --bind "start:execute-silent($self --refresh)" \
  --bind "load:pos(${cur:-1})" \
  --bind 'j:down,k:up,ctrl-r:refresh-preview,q:abort' \
  --bind 's:show-input+unbind(j,k,s,q)' \
  --bind 'esc:clear-query+transform([ "$FZF_INPUT_STATE" = hidden ] && echo abort || echo "hide-input+rebind(j,k,s,q)")' \
  --bind "down:execute-silent($self --pane 1 {1})+refresh-preview" \
  --bind "up:execute-silent($self --pane -1 {1})+refresh-preview" \
  || true)

[[ -n $pick ]] || exit 0
if [[ $pick == RESIZE* ]]; then
  title=' windows '; args="--select '${pick#RESIZE	}' '$session' '$client'"
  (( all )) && { title=' sessions '; args="--all $args"; }
  tmux run-shell -b "sleep 0.3; tmux display-popup -c '$client' -E -w 95% -h 95% -T '$title' \"$self $args\""
  exit 0
fi
target=$(selected_pane "${pick%%	*}")
tmux switch-client -c "$client" -t "${target:-${pick%%	*}}" \
  || tmux display-message -c "$client" "window-chooser: switch failed (client $client, target ${target:-${pick%%	*}})"
