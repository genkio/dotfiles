#!/usr/bin/env bash
set -euo pipefail
window=$1
session=$2
client=$3

default=tmp

if [ "$session" = "$default" ]; then
  tmux display-message "already in $default"
  exit 0
fi

if tmux has-session -t "=$default" 2>/dev/null; then
  tmux move-window -s "$window" -t "$default:"
else
  placeholder=$(tmux new-session -dP -F '#{window_id}' -s "$default")
  tmux move-window -s "$window" -t "$default:"
  tmux kill-window -t "$placeholder"
  tmux move-window -r -t "$default"
fi

tmux switch-client -c "$client" -t "$default"
