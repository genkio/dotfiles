#!/usr/bin/env bash

set -euo pipefail

if ! tmux info >/dev/null 2>&1; then
  exit 0
fi

theme="$("${DOTFILES_DIR:-$HOME/dotfiles}/scripts/current-theme.sh")"

if [ "$theme" = "dark" ]; then
  term_bg='#24283b'
  bg='#1f2335'
  fg='#a9b1d6'
  muted='#565f89'
  border='#414868'
  active_border='#7aa2f7'
  current_bg='#3b4261'
  current_fg='#c0caf5'
  attention='#f7768e'
  busy='#e0af68'
  awaiting='#9ece6a'
else
  term_bg='#fffcf0'
  bg='#e6e4d9'
  fg='#6f6e69'
  muted='#878580'
  border='#b7b5ac'
  active_border='#205EA6'
  current_bg='#fffcf0'
  current_fg='#100f0f'
  attention='#af3029'
  busy='#ad8301'
  awaiting='#66800b'
fi

tmux set-option -g window-style "bg=$term_bg"
tmux set-option -g window-active-style "bg=$term_bg"

agent_prefix='#{?@agent_attention,#[fg='"$attention"'#,bold],#{?@agent_busy,#[fg='"$busy"'#,bold],#{?@agent_awaiting,#[fg='"$awaiting"'#,bold],}}}'

pane_state_inactive='#{?#{==:#{@agent_pane_state},attention},fg='"$attention"',#{?#{==:#{@agent_pane_state},busy},fg='"$busy"',#{?#{==:#{@agent_pane_state},awaiting},fg='"$awaiting"',fg='"$border"'}}}'
tmux set-option -g pane-border-style "$pane_state_inactive"
tmux set-option -g pane-active-border-style "fg=$active_border"

tmux set-option -g popup-style "bg=$term_bg,fg=$fg"
tmux set-option -g popup-border-style "fg=$border,bg=$term_bg"

tmux set-option -g status-style "bg=$bg,fg=$fg"
tmux set-option -g status-left-style "bg=$bg,fg=$fg"
tmux set-option -g status-right-style "bg=$bg,fg=$fg"
muted_hex="${muted#\#}"
attention_hex="${attention#\#}"
busy_hex="${busy#\#}"
usage_cmd="\$HOME/dotfiles/tmux/bin/status-usage.sh $muted_hex $attention_hex $busy_hex"
tmux set-option -g status-left "#[fg=$muted]#{?@status_show_all,#($usage_cmd all),#($usage_cmd)}#[default]"
usage_segment="#[fg=$muted]#(~/.tmux/plugins/tmux-open-usage/scripts/open_usage_status.sh)#[default]"
tmux set-option -g status-right "#{?#{||:#{@usage_hidden},#{m:*ssh*,#{pane_current_command}}},,$usage_segment}"

tmux set-option -g @off_chip "#[bg=$active_border,fg=$term_bg,bold] ⇥ REMOTE (F12) #[default]"

tmux set-option -g window-status-style "bg=$bg,fg=$fg"
tmux set-option -g window-status-current-style "bg=$current_bg,fg=$current_fg"
tmux set-option -g window-status-format "${agent_prefix} #W#F "
tmux set-option -g window-status-current-format "${agent_prefix} #[bold]#W#F "

tmux set-option -g @gh-pr-glamour-style "$theme"
