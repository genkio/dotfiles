# This file exists so zsh shells spawned by Neovim `:!` can load command
# helpers like `gpu()`; non-interactive zsh reads `.zshenv`, not `.zshrc`.
if [[ -n "$NVIM_SHELL_ALIASES" ]]; then
  [[ -f ~/.zsh_aliases ]] && source ~/.zsh_aliases
fi
