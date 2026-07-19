#!/usr/bin/env bash
#
# Apply the Flexoki Light / TokyoNight Storm palette to tmux for the current
# theme (current-theme.sh). Sourced from .tmux.conf at startup/reload and re-run
# by theme-toggle.sh on a flip.

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
  # blue, not green: awaiting panes use green borders, active must differ
  active_border='#7aa2f7'
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
  # blue, not green: awaiting panes use green borders, active must differ
  active_border='#205EA6'
  current_bg='#fffcf0'
  current_fg='#100f0f'
  attention='#af3029'
  busy='#ad8301'
  awaiting='#66800b'
fi

# `#,` inside a `#{?cond,then,else}` conditional escapes the comma so it
# isn't treated as the field separator. Build the agent-state prefix once.
agent_prefix='#{?@agent_attention,#[fg='"$attention"'#,bold],#{?@agent_busy,#[fg='"$busy"'#,bold],#{?@agent_awaiting,#[fg='"$awaiting"'#,bold],}}}'

# Inactive panes show their agent state via @agent_pane_state (set by the
# agent-{busy,attention,idle}.sh hooks on the agent's own pane): red when
# that pane needs approval, orange while it works, green when it finished,
# otherwise the theme default. tmux expands the style per pane, so each
# background pane's border reflects its own agent independently.
# attention outranks busy outranks awaiting.
#
# The active pane always keeps the plain active-border colour and ignores
# @agent_pane_state: the focused pane should read as "here", and you can
# already see what its agent is doing. Agent state is the signal for the
# panes you are NOT watching. Leaving a busy/awaiting pane reveals its
# colour as it goes inactive; focusing one resets it to the active border
# (and, via the pane-focus-in hook in .tmux.conf, clears a green for good).
pane_state_inactive='#{?#{==:#{@agent_pane_state},attention},fg='"$attention"',#{?#{==:#{@agent_pane_state},busy},fg='"$busy"',#{?#{==:#{@agent_pane_state},awaiting},fg='"$awaiting"',fg='"$border"'}}}'
tmux set-option -g pane-border-style "$pane_state_inactive"
tmux set-option -g pane-active-border-style "fg=$active_border"

tmux set-option -g status-style "bg=$bg,fg=$fg"
tmux set-option -g status-left-style "bg=$bg,fg=$fg"
tmux set-option -g status-right-style "bg=$bg,fg=$fg"
# strip the leading # from the theme colors so they can't start a shell
# comment inside the #() arguments below.
muted_hex="${muted#\#}"
attention_hex="${attention#\#}"
busy_hex="${busy#\#}"
# status-usage.sh owns every conditional color in the left block (cpu offline,
# ram maestral/dropbox state, low battery); pass the palette so tints track the theme.
tmux set-option -g status-left "#[fg=$muted]#(\$HOME/dotfiles/tmux/bin/status-usage.sh $muted_hex $attention_hex $busy_hex)#[default]"
# open_usage_status.sh inlined, not the plugin's auto-inject (@tmux_open_usage_enabled
# off), so it takes the theme color instead of the plugin's fixed gray and never dupes.
tmux set-option -g status-right "#[fg=$muted]#(~/.tmux/plugins/tmux-open-usage/scripts/open_usage_status.sh)#[default] [%H:%M]"

tmux set-option -g window-status-style "bg=$bg,fg=$fg"
tmux set-option -g window-status-current-style "bg=$current_bg,fg=$current_fg"
tmux set-option -g window-status-format "${agent_prefix} #I:#W#F "
tmux set-option -g window-status-current-format "${agent_prefix} #[bold]#I:#W#F "

# choose-tree (prefix+w / C-Down) window rows reuse the same agent colours.
# -F replaces the whole row, so this is tmux's stock tree format (copied from
# 3.7b; may need a refresh if a tmux upgrade changes the default) with
# agent_prefix injected at the head of the window branch. Published as an
# option and read by the bindings via #{E:@tree_format} so colours track the
# theme without rebinding keys here.
tree_format='#{?pane_format,#{?pane_marked,#[reverse],}#{?pane_floating_flag,#[italics],}#{pane_current_command}#{pane_flags}#{?#{&&:#{pane_title},#{!=:#{pane_title},#{host_short}}},: "#{pane_title}",},window_format,'"${agent_prefix}"'#{?window_marked_flag,#[reverse],}#{window_name}#{window_flags}#{?#{&&:#{==:#{window_panes},1},#{&&:#{pane_title},#{!=:#{pane_title},#{host_short}}}},: "#{pane_title}",},#{session_windows} windows#{?session_grouped, (group #{session_group}: #{session_group_list}),}#{?session_attached, (attached),}}'
tmux set-option -g @tree_format "$tree_format"
