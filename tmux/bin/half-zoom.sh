#!/usr/bin/env bash
set -euo pipefail
pane=$1
win=$2
dim=$3

opt="@hz_maxed_$dim"
maxed=$(tmux show -wqv -t "$win" "$opt")

live=$(tmux list-panes -t "$win" -F '#{pane_id}' | tr '\n' ' ')
kept=""; found=0
for p in $maxed; do
  case " $live " in *" $p "*) ;; *) continue ;; esac
  if [ "$p" = "$pane" ]; then found=1; else kept="$kept $p"; fi
done

if [ "$found" = 1 ]; then
  tmux select-layout -t "$pane" -E
  tmux set -w -t "$win" "$opt" "$kept"
else
  tmux resize-pane -t "$pane" "-$dim" 9999
  tmux set -w -t "$win" "$opt" "$kept $pane"
fi
