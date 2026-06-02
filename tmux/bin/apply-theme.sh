#!/usr/bin/env bash
#
# Apply Flexoki Light (light) or TokyoNight Storm (dark) palette to tmux based
# on the current macOS appearance. Sourced from .tmux.conf at startup/reload,
# and re-run by Hammerspoon when AppleInterfaceThemeChangedNotification
# fires so the status bar tracks system appearance live.

set -euo pipefail

# No-op if tmux isn't running; avoid spawning a new server.
if ! tmux info >/dev/null 2>&1; then
  exit 0
fi

theme="$("${DOTFILES_DIR:-$HOME/dotfiles}/scripts/current-theme.sh")"

if [ "$theme" = "dark" ]; then
  # TokyoNight Storm (status bar recedes below the #24283b editor surface)
  bg='#1f2335'
  fg='#a9b1d6'
  muted='#565f89'
  border='#414868'
  active_border='#9ece6a'
  current_bg='#3b4261'
  current_fg='#c0caf5'
  attention='#f7768e'
  busy='#e0af68'
  awaiting='#9ece6a'
else
  # Flexoki Light (status bar recedes below the #fffcf0 paper editor surface)
  bg='#e6e4d9'
  fg='#6f6e69'
  muted='#878580'
  border='#b7b5ac'
  active_border='#66800b'
  current_bg='#fffcf0'
  current_fg='#100f0f'
  attention='#af3029'
  busy='#ad8301'
  awaiting='#66800b'
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
