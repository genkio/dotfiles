export LANG=en_US.UTF-8
export LC_MESSAGES=en_US.UTF-8
export HOMEBREW_NO_PROGRESS_BARS=1
export EDITOR="nvim"
export VISUAL="$EDITOR"

if [[ -z "${HOMEBREW_PREFIX:-}" ]]; then
  for _brew in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [[ -x "$_brew" ]] && eval "$("$_brew" shellenv)" && break
  done
  unset _brew
fi
export PATH="$HOME/.local/bin:$PATH"
export GPG_TTY=$(tty)
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=()

if [[ -o interactive && -n "$SSH_CONNECTION" && -z "$TMUX" && -z "$NO_AUTO_TMUX" ]] && command -v tmux >/dev/null 2>&1; then
  exec tmux new -A -s "${TMUX_DEFAULT_SESSION:-tmp}"
fi

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

export PI_SKIP_VERSION_CHECK=1
command -v mise >/dev/null 2>&1 && eval "$(mise activate zsh)"

[[ -f ~/.zsh_prompt ]] && source ~/.zsh_prompt

command -v fzf >/dev/null 2>&1 && source <(fzf --zsh)

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

for k in U D J K; do
  bindkey -M viins -s "^[$k" ''
  bindkey -M emacs -s "^[$k" ''
done
unset k

[[ -f "$HOME/.local/bin/env" ]] && . "$HOME/.local/bin/env"
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local

[[ -d "$HOME/Library/Mobile Documents/com~apple~CloudDocs" && ! -e ~/icloud ]] && \
  ln -s "$HOME/Library/Mobile Documents/com~apple~CloudDocs" ~/icloud

[[ -f ~/.zsh_aliases ]] && source ~/.zsh_aliases

command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh)"
