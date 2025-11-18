export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git)

source $ZSH/oh-my-zsh.sh
source <(fzf --zsh)

# Local env (only if it exists)
[ -f "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env"

# Alias
alias ip='ipconfig getifaddr en0'

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
