export LANG=en_US.UTF-8
export LC_MESSAGES=en_US.UTF-8
export HOMEBREW_NO_PROGRESS_BARS=1
export EDITOR="nvim"

export PATH="$HOME/.local/bin:$PATH"
export GPG_TTY=$(tty)
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=()

# Keep Ghostty shell integration active in shells launched by tmux or `exec zsh`.
if [[ -n "$GHOSTTY_RESOURCES_DIR" && -r "$GHOSTTY_RESOURCES_DIR/shell-integration/zsh/ghostty-integration" ]]; then
  source "$GHOSTTY_RESOURCES_DIR/shell-integration/zsh/ghostty-integration"
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

set -o vi
setopt HIST_IGNORE_SPACE
setopt HIST_IGNORE_DUPS
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

# Machine-specific env / config (not tracked by git)
[[ -f "$HOME/.local/bin/env" ]] && . "$HOME/.local/bin/env"
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local

# Create iCloud symlink if missing
[[ -d "$HOME/Library/Mobile Documents/com~apple~CloudDocs" && ! -e ~/icloud ]] && \
  ln -s "$HOME/Library/Mobile Documents/com~apple~CloudDocs" ~/icloud

# Aliases and helper functions (managed as ~/.zsh_aliases via stow)
[[ -f ~/.zsh_aliases ]] && source ~/.zsh_aliases

# Bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# Rust
export PATH="$HOME/.cargo/bin:$PATH"

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
export SDKMAN_DIR="$(brew --prefix sdkman-cli)/libexec"
[[ -s "${SDKMAN_DIR}/bin/sdkman-init.sh" ]] && source "${SDKMAN_DIR}/bin/sdkman-init.sh"
