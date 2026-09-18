#!/usr/bin/env bash
set -euo pipefail
pane=$1
window=$2
cwd=$3

new=$(tmux new-session -dP -F '#{session_name}')
tmux join-pane -s "$pane" -t "$new:"
tmux kill-pane -a -t "$pane"

tmux_bin=$(command -v tmux)

if ! alacritty msg create-window --working-directory "$cwd" -e "$tmux_bin" attach -t "=$new" 2>/dev/null; then
  env -u TMUX -u TMUX_PANE alacritty --working-directory "$cwd" -e "$tmux_bin" attach -t "=$new" &
fi

tmux select-layout -t "$window" -E 2>/dev/null || true
