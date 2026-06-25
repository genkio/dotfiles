#!/usr/bin/env bash
# C-x "half zoom": maximize the current pane to fill its column (the left/right
# half), unlike C-z full zoom which takes the whole window. tmux has no per-pane
# hide, so the pane sharing the column collapses to a 1-row sliver. Columns are
# independent subtrees, so one pane per column can be maxed at once. Each press
# maxes or re-evens only the pressed pane's column, leaving other maxed columns
# untouched; @hz_maxed tracks the maxed set to tell the two presses apart.
set -euo pipefail
pane=$1
win=$2

maxed=$(tmux show -wqv -t "$win" @hz_maxed)

# drop ids whose pane is gone (a stale id would linger in the set forever) and
# note whether the pressed pane is already maxed
live=$(tmux list-panes -t "$win" -F '#{pane_id}' | tr '\n' ' ')
kept=""; found=0
for p in $maxed; do
  case " $live " in *" $p "*) ;; *) continue ;; esac
  if [ "$p" = "$pane" ]; then found=1; else kept="$kept $p"; fi
done

if [ "$found" = 1 ]; then
  tmux select-layout -t "$pane" -E
  tmux set -w -t "$win" @hz_maxed "$kept"
else
  tmux resize-pane -t "$pane" -y 9999   # oversized; tmux clamps to the column max
  tmux set -w -t "$win" @hz_maxed "$kept $pane"
fi
