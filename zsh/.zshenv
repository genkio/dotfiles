export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$HOME/dotfiles/scripts:$PATH"

if [[ -n "$NVIM_SHELL_ALIASES" ]]; then
  [[ -f ~/.zsh_aliases ]] && source ~/.zsh_aliases
fi
