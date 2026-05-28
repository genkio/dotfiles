#!/usr/bin/env bash
#
# Apply Dawnfox (light) or Nordfox (dark) palette to tmux based on the
# current macOS appearance. Sourced from .tmux.conf at startup/reload,
# and re-run by Hammerspoon when AppleInterfaceThemeChangedNotification
# fires so the status bar tracks system appearance live.

set -euo pipefail

# No-op if tmux isn't running; avoid spawning a new server.
if ! tmux info >/dev/null 2>&1; then
  exit 0
fi

if defaults read -g AppleInterfaceStyle 2>/dev/null | grep -q Dark; then
  # Nordfox
  bg='#232831'
  fg='#abb1bb'
  muted='#60728a'
  border='#5a657d'
  active_border='#a3be8c'
  current_bg='#444c5e'
  current_fg='#cdcecf'
  attention='#bf616a'
  busy='#ebcb8b'
  awaiting='#a3be8c'
else
  # Dawnfox
  bg='#ebe5df'
  fg='#625c87'
  muted='#9893a5'
  border='#bdbfc9'
  active_border='#618774'
  current_bg='#faf4ed'
  current_fg='#575279'
  attention='#b4637a'
  busy='#ea9d34'
  awaiting='#618774'
fi

# `#,` inside a `#{?cond,then,else}` conditional escapes the comma so it
# isn't treated as the field separator. Build the agent-state prefix once.
agent_prefix='#{?@agent_attention,#[fg='"$attention"'#,bold],#{?@agent_busy,#[fg='"$busy"'#,bold],#{?@agent_awaiting,#[fg='"$awaiting"'#,bold],}}}'

tmux set-option -g pane-border-style "fg=$border"
tmux set-option -g pane-active-border-style "fg=$active_border"

tmux set-option -g status-style "bg=$bg,fg=$fg"
tmux set-option -g status-left-style "bg=$bg,fg=$fg"
tmux set-option -g status-right-style "bg=$bg,fg=$fg"
tmux set-option -g status-left "#[fg=$muted]#(\$HOME/dotfiles/tmux/bin/status-usage.sh)#[default]"
tmux set-option -g status-right "#[fg=$muted]#(~/.tmux/plugins/tmux-open-usage/scripts/open_usage_status.sh)#[default] [%H:%M]"

tmux set-option -g window-status-style "bg=$bg,fg=$fg"
tmux set-option -g window-status-current-style "bg=$current_bg,fg=$current_fg"
tmux set-option -g window-status-format "${agent_prefix} #I:#W#F "
tmux set-option -g window-status-current-format "${agent_prefix} #[bold]#I:#W#F "
