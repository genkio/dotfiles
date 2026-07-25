#!/usr/bin/env bash
# Reverse of prefix+B (pop a pane into a brand-new session): gather a window
# back into the default session and follow it. A session left with no windows
# dies on its own, so a session spawned by B evaporates once its window comes
# home. Indexless `-t tmp:` drops the window at the FIRST FREE index (so it
# fills a gap left by an earlier kill, keeping cmd+digit jumps dense) and never
# clashes; swap in `-a -t "$default:{end}"` if you'd rather always append.
set -euo pipefail
window=$1
session=$2
client=$3

default=tmp   # the session `tx` attaches to

if [ "$session" = "$default" ]; then
  tmux display-message "already in $default"
  exit 0
fi

if tmux has-session -t "=$default" 2>/dev/null; then
  tmux move-window -s "$window" -t "$default:"
else
  # recreate it, then drop its placeholder shell (same trick as prefix+B).
  # renumber afterwards so we don't start at index 1 in the placeholder's wake -
  # safe here only because our window is the session's sole survivor
  placeholder=$(tmux new-session -dP -F '#{window_id}' -s "$default")
  tmux move-window -s "$window" -t "$default:"
  tmux kill-window -t "$placeholder"
  tmux move-window -r -t "$default"
fi

# pin to the client tty: the move may destroy our old session, which reassigns
# the client out from under a bare switch-client
tmux switch-client -c "$client" -t "$default"
