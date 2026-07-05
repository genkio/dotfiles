#!/usr/bin/env bash
# "half zoom": maximize the current pane along ONE axis to fill its column or
# row, unlike C-z full zoom which takes the whole window. tmux has no per-pane
# hide, so the pane sharing that column/row collapses to a 1-cell sliver.
# Columns/rows are independent subtrees, so one pane per column and one per row
# can be maxed at once. Each press maxes or re-evens only the pressed pane's
# column/row (select-layout -E spreads just the current pane's siblings),
# leaving other maxed panes untouched. @hz_maxed_$dim tracks the maxed set per
# axis, both to tell the two presses apart and to keep the axes independent.
#
# $dim is the tmux resize-pane dimension, the opposite letter to the axis filled:
#   dim=y  grow height -> fill the column (C-x, full vertical space)
#   dim=x  grow width  -> fill the row    (C-y, full horizontal space)
set -euo pipefail
pane=$1
win=$2
dim=$3

opt="@hz_maxed_$dim"
maxed=$(tmux show -wqv -t "$win" "$opt")

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
  tmux set -w -t "$win" "$opt" "$kept"
else
  tmux resize-pane -t "$pane" "-$dim" 9999   # oversized; tmux clamps to the column/row max
  tmux set -w -t "$win" "$opt" "$kept $pane"
fi
