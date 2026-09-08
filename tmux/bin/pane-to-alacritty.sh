#!/usr/bin/env bash
# Third sibling of prefix+b (pane -> new window) and prefix+B (pane -> new
# session): pop the pane into a new session AND open an Alacritty window on it,
# leaving this client where it is. Same detached-session + join-pane trick as B,
# since tmux cannot break straight to a new session.
set -euo pipefail
pane=$1
window=$2
cwd=$3

new=$(tmux new-session -dP -F '#{session_name}')
tmux join-pane -s "$pane" -t "$new:"
tmux kill-pane -a -t "$pane"   # the new session's placeholder shell

# Absolute tmux: `msg create-window` runs -e with the env of the ALREADY-RUNNING
# Alacritty, and a GUI-launched app's PATH has no ~/.local/bin - a bare `tmux`
# there exits instantly and the window vanishes with it.
tmux_bin=$(command -v tmux)

# msg reuses that running instance (its cwd too, hence --working-directory).
# Nothing running -> spawn one, and drop TMUX/TMUX_PANE, which leak in from
# run-shell and make the new client refuse to attach as "nested".
if ! alacritty msg create-window --working-directory "$cwd" -e "$tmux_bin" attach -t "=$new" 2>/dev/null; then
  env -u TMUX -u TMUX_PANE alacritty --working-directory "$cwd" -e "$tmux_bin" attach -t "=$new" &
fi

# window_id may already be gone if the pane was its window's last one
tmux select-layout -t "$window" -E 2>/dev/null || true
