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
  term_bg='#24283b'
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
  term_bg='#fffcf0'
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

# tmux answers an app's OSC 11 "what is your background?" query from window-style
# when that style names a colour, and otherwise replays what the client terminal
# reported at ATTACH time - a value it never re-queries. apply-terminal-colors.sh
# repaints the live terminal by writing OSC straight to each client tty, so a flip
# leaves that cache stale and TUIs that pick their palette from the query (Codex,
# delta, bat) render the wrong one: light-mode cream surfaces on a dark terminal.
# Naming the real bg here keeps the answer honest across a flip and across clients
# (Mac + phone SSH), and paints the colour the terminal already uses, so panes look
# unchanged.
tmux set-option -g window-style "bg=$term_bg"
tmux set-option -g window-active-style "bg=$term_bg"

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

# popups (prefix + F/P pickers, prefix + T clock) default to the terminal's
# own colors, which after an OSC flip is whatever it was at attach time. Name
# them so an overlay never lands light-on-light.
tmux set-option -g popup-style "bg=$term_bg,fg=$fg"
tmux set-option -g popup-border-style "fg=$border,bg=$term_bg"

tmux set-option -g status-style "bg=$bg,fg=$fg"
tmux set-option -g status-left-style "bg=$bg,fg=$fg"
tmux set-option -g status-right-style "bg=$bg,fg=$fg"
# strip the leading # from the theme colors so they can't start a shell
# comment inside the #() arguments below.
muted_hex="${muted#\#}"
attention_hex="${attention#\#}"
busy_hex="${busy#\#}"
# status-usage.sh owns the whole left block and prints nothing while the machine
# is healthy - it only names the signals worth a look (cpu, ram, net, dropbox,
# battery). Pass the palette so its tints track the theme.
#
# @status_show_all is the prefix+S toggle: gated in the format for the same
# reason as @usage_hidden below, so a theme flip re-running this script keeps
# whichever mode the bar is in. The two branches are two distinct #() command
# strings, i.e. two tmux jobs, so flipping shows the other one's output on its
# first run rather than a stale line.
usage_cmd="\$HOME/dotfiles/tmux/bin/status-usage.sh $muted_hex $attention_hex $busy_hex"
tmux set-option -g status-left "#[fg=$muted]#{?@status_show_all,#($usage_cmd all),#($usage_cmd)}#[default]"
# No clock here: it cost 8 permanent columns to answer a question asked a few
# times a day, and prefix + C now opens a popup with the date and calendar too.
# open_usage_status.sh inlined, not the plugin's auto-inject (@tmux_open_usage_enabled
# off), so it takes the theme color instead of the plugin's fixed gray and never dupes.
#
# Blank on an ssh pane: the remote runs these same dotfiles, so its own status
# bar prints the same numbers one row up. Status formats expand against the
# session's current pane, so this flips per window with no hook. *ssh* also
# catches autossh/sshpass.
#
# @usage_hidden is the prefix+u toggle: gate the format rather than rewrite
# status-right, else a theme flip re-running this script resurrects a hidden
# bar. tmux expands only the taken branch, so hiding stops the usage fetch as
# well, exactly like an ssh pane already does.
usage_segment="#[fg=$muted]#(~/.tmux/plugins/tmux-open-usage/scripts/open_usage_status.sh)#[default]"
tmux set-option -g status-right "#{?#{||:#{@usage_hidden},#{m:*ssh*,#{pane_current_command}}},,$usage_segment}"

# Chip shown by the F12 off-mode binding (see .tmux.conf). Published as an
# option so the colour tracks the theme without the binding hardcoding one.
# The blue is the active-border accent, deliberately not `attention` red or
# `busy` orange: those two mean "an agent needs you" everywhere else.
tmux set-option -g @off_chip "#[bg=$active_border,fg=$term_bg,bold] ⇥ REMOTE (F12) #[default]"

tmux set-option -g window-status-style "bg=$bg,fg=$fg"
tmux set-option -g window-status-current-style "bg=$current_bg,fg=$current_fg"
# no #I: prefix - the name carries the meaning. Indexes still exist for
# prefix+0-9 and Cmd+1-9; `tmux list-windows` prints them when one is unclear.
tmux set-option -g window-status-format "${agent_prefix} #W#F "
tmux set-option -g window-status-current-format "${agent_prefix} #[bold]#W#F "

# tmux-gh-pr renders PR markdown via gh/glamour, which can't see the
# terminal bg from inside a popup; tell it which stylesheet to use
tmux set-option -g @gh-pr-glamour-style "$theme"
