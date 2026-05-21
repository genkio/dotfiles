#!/usr/bin/env bash
# Clear @agent_busy / @agent_awaiting / @agent_attention on every
# window across every session on the running tmux server.
#
# Intended uses:
#   - One-time sweep at tmux server start, in case any prior server
#     lifetime left these per-window options set (e.g. a future plugin
#     starts persisting them, or a custom resurrect save script does).
#   - Post-tmux-resurrect-restore sweep, same reason.
#   - Manual invocation when the user sees a stuck overlay because an
#     agent died without firing its Stop hook.

set -u
command -v tmux >/dev/null 2>&1 || exit 0

tmux list-windows -a -F '#{window_id}' 2>/dev/null | while read -r wid; do
  [ -n "$wid" ] || continue
  tmux set-window-option -q -t "$wid" @agent_busy 0
  tmux set-window-option -q -t "$wid" @agent_awaiting 0
  tmux set-window-option -q -t "$wid" @agent_attention 0
done
exit 0
