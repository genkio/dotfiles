#!/usr/bin/env bash

set -u
command -v tmux >/dev/null 2>&1 || exit 0

tmux list-windows -a -F '#{window_id}' 2>/dev/null | while read -r wid; do
  [ -n "$wid" ] || continue
  tmux set-window-option -q -t "$wid" @agent_busy 0
  tmux set-window-option -q -t "$wid" @agent_awaiting 0
  tmux set-window-option -q -t "$wid" @agent_attention 0
done

tmux list-panes -a -F '#{pane_id}' 2>/dev/null | while read -r pid; do
  [ -n "$pid" ] || continue
  tmux set-option -p -q -u -t "$pid" @agent_pane_state
done

tmux list-clients -F '#{client_name}' 2>/dev/null | while read -r c; do
  [ -n "$c" ] && tmux refresh-client -t "$c"
done
exit 0
