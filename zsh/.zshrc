# Main interactive zsh startup file for the stowed shell profile.
#
# This sets the shared environment, loads Oh My Zsh, installs a few interactive
# conveniences, and then hands off to the smaller sourced files for prompt,
# aliases, and machine-local overrides. Keep machine-specific values in
# ~/.zshrc.local or ~/.local/bin/env rather than in this tracked file.

export LANG=en_US.UTF-8
export LC_MESSAGES=en_US.UTF-8
export HOMEBREW_NO_PROGRESS_BARS=1
export EDITOR="nvim"
export VISUAL="$EDITOR"

export PATH="$HOME/.local/bin:$PATH"
# Apple Silicon puts brew in /opt/homebrew, which is not in the default PATH, so
# without this a fresh terminal on arm64 cannot find brew at all. Intel's
# /usr/local/bin is already in /etc/paths, but shellenv still adds the
# HOMEBREW_*/MANPATH/INFOPATH vars. Guarded so nested shells skip the fork.
if [[ -z "${HOMEBREW_PREFIX:-}" ]]; then
  for _brew in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [[ -x "$_brew" ]] && eval "$("$_brew" shellenv)" && break
  done
  unset _brew
fi
export GPG_TTY=$(tty)
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=()

# Auto-attach interactive SSH logins to the default tmux session.
# Set NO_AUTO_TMUX=1 before starting the shell to bypass this.
if [[ -o interactive && -n "$SSH_CONNECTION" && -z "$TMUX" && -z "$NO_AUTO_TMUX" ]] && command -v tmux >/dev/null 2>&1; then
  exec tmux new -A -s "${TMUX_DEFAULT_SESSION:-tmp}"
fi

# Auto-install Oh My Zsh if missing (keep existing .zshrc)
if [ ! -d "$ZSH" ]; then
  if command -v curl >/dev/null 2>&1; then
    echo "Oh My Zsh not found. Installing to $ZSH..."
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c \
      "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  else
    echo "Oh My Zsh not found and curl is missing. Please install curl and rerun."
  fi
fi

source $ZSH/oh-my-zsh.sh

# Custom prompt (managed as ~/.zsh_prompt via stow)
[[ -f ~/.zsh_prompt ]] && source ~/.zsh_prompt

source <(fzf --zsh)

# Keep SSH_* in long-lived tmux panes in sync with the newest client attach.
# tmux update-environment (see .tmux.conf) refreshes the *session* environment,
# but shells that already run keep their stale copy, so pam_reattach's
# ignore_ssh can't tell a remote attach from a local one and sudo pops Touch ID
# on the physical screen instead of asking for a password. Re-export before
# every prompt so sudo always sees the current attach type.
if [[ -n "$TMUX" ]]; then
  _tmux_refresh_ssh_env() {
    local line
    for line in "${(@f)$(command tmux show-environment 2>/dev/null)}"; do
      case "$line" in
        SSH_CONNECTION=*|SSH_CLIENT=*|SSH_TTY=*) export "$line" ;;
        -SSH_CONNECTION|-SSH_CLIENT|-SSH_TTY) unset "${line#-}" ;;
      esac
    done
  }
  autoload -Uz add-zsh-hook
  add-zsh-hook precmd _tmux_refresh_ssh_env
fi

set -o vi
setopt HIST_IGNORE_SPACE
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_FIND_NO_DUPS
setopt HIST_REDUCE_BLANKS
setopt HIST_SAVE_NO_DUPS
setopt HIST_EXPIRE_DUPS_FIRST

add-history-space() {
  [[ $BUFFER == ' '* ]] && return

  BUFFER=" $BUFFER"
  (( CURSOR++ ))
}

remove-history-space() {
  [[ $BUFFER != ' '* ]] && return

  BUFFER="${BUFFER# }"
  (( CURSOR > 0 )) && (( CURSOR-- ))
}

zle -N add-history-space
zle -N remove-history-space
bindkey -M viins '^[a' add-history-space
bindkey -M emacs '^[a' add-history-space
bindkey -M viins '^[d' remove-history-space
bindkey -M emacs '^[d' remove-history-space
bindkey -M viins '^a' beginning-of-line
bindkey -M viins '^e' end-of-line

# Cmd/Opt+Shift+u/d/j/k are Claude Code scroll chords (Alacritty emits
# ESC+letter). Unbound they split into ESC -> vicmd, where D kills to eol.
# Swallow so a fat-finger at the prompt does nothing.
for k in U D J K; do
  bindkey -M viins -s "^[$k" ''
  bindkey -M emacs -s "^[$k" ''
done
unset k

# Machine-specific env / config (not tracked by git)
[[ -f "$HOME/.local/bin/env" ]] && . "$HOME/.local/bin/env"
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local

# Create iCloud symlink if missing
[[ -d "$HOME/Library/Mobile Documents/com~apple~CloudDocs" && ! -e ~/icloud ]] && \
  ln -s "$HOME/Library/Mobile Documents/com~apple~CloudDocs" ~/icloud

# Aliases and helper functions (managed as ~/.zsh_aliases via stow)
[[ -f ~/.zsh_aliases ]] && source ~/.zsh_aliases

# mise: node, python, java, go, uv + global npm tools
eval "$(mise activate zsh)"

eval "$(zoxide init zsh)"
