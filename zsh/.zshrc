export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git)

source $ZSH/oh-my-zsh.sh
source <(fzf --zsh)

# Local env (only if it exists)
[ -f "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env"

# Alias
alias cc='claude'
alias cx='codex'
alias oc='opencode'
alias lg='lazygit'
alias ld='lazydocker'
alias ip='ipconfig getifaddr en0'
alias tx='tmux'
alias txp='[ -f "$HOME/tmuxp.yaml" ] && tmuxp load -y $HOME/tmuxp.yaml || tmux new-session -s tmp'

# Git shortcuts (custom)
alias gs='git status'
alias glo='git log --pretty --oneline -5'
alias gad='git add .'

# Avoid conflicts with oh-my-zsh git aliases
unalias gcm gpl gundo gpu gpuf gbr gco 2>/dev/null

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

#THIS MUST BE AT THE END OF THE FILE FOR SDKMAN TO WORK!!!
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"
