export LANG=en_US.UTF-8
export LC_MESSAGES=en_US.UTF-8

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=()

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
source <(fzf --zsh)

set -o vi

# Local env (only if it exists)
[ -f "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env"

# Alias
alias cc='claude'
alias cx='codex'
alias oc='opencode'
alias lg='lazygit'
alias ld='lazydocker'
alias ip='ipconfig getifaddr en0'
alias txp='tmuxp load -y'

TMUX_DEFAULT_SESSION="tmp"

tx() {
  if [[ -n "$1" ]]; then
    tmux a -t "$1"
  else
    tmux new -A -s "$TMUX_DEFAULT_SESSION"
  fi
}

ssht() {
  TERM=xterm-256color ssh -t "$1" "tmux new -A -s $TMUX_DEFAULT_SESSION"
}

# Git shortcuts (custom)
alias gs='git status'
alias glo='git log --pretty --oneline -5'
alias gad='git add .'

alias gco='git checkout'
# list 10 most recent branches with commit dates
alias gbr='git for-each-ref --sort=-committerdate refs/heads/ --format="%(committerdate:short) %(refname:short)" --count=10'
# list staged file names
alias gst='git diff --name-only --cached'

# git commit -m "<message>"
gcm() {
  if [ $# -eq 0 ]; then
    echo "usage: gcm <message>" >&2
    return 1
  fi
  git commit -m "$*"
}

# git pull origin <current-branch>
gpl() {
  local br
  br=$(git symbolic-ref --short HEAD) || return
  git pull origin "$br"
}

# git push origin <current-branch>
gpu() {
  local br
  br=$(git symbolic-ref --short HEAD) || return
  git push origin "$br"
}

# git push origin <current-branch> --force-with-lease
gpuf() {
  local br
  br=$(git symbolic-ref --short HEAD) || return
  git push origin "$br" --force-with-lease
}

gundo() {
  git reset --soft HEAD~1
}

# Tmux wrapper - set compatible TERM before launching
if command -v tmux &> /dev/null && [ -z "$TMUX" ]; then
  alias tmux='TERM=tmux-256color tmux'
fi

# Volta
export VOLTA_HOME="$HOME/.volta"
export PATH="$VOLTA_HOME/bin:$PATH"
export VOLTA_FEATURE_PNPM=1

# pyenv
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

eval "$(zoxide init zsh)"

# Machine-specific config (not tracked by git)
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local

#THIS MUST BE AT THE END OF THE FILE FOR SDKMAN TO WORK!!!
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"
