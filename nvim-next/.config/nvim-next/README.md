# nvim-next

Clean Neovim 0.12 sandbox launched with:

```sh
NVIM_APPNAME=nvim-next nvim
```

`<leader>` is `Space`.

## Behaviors

- Files changed on disk are reloaded automatically for normal file buffers.
- `updatetime` is set to `250ms` so `CursorHold`-based reloads feel responsive in tmux.
- `nvim .` reopens the last real file you had focused in that directory.
- TypeScript LSP is enabled through core Neovim 0.12 `vim.lsp` using `ts_ls`.
- Search defaults to the current working directory, not the git root.
- When the cwd is inside `~/dotfiles`, picker searches include hidden files and exclude `.git`.
- `<leader>sS` can reuse a compatible project LSP from another open buffer when the current buffer itself has no attached LSP.

## Snacks.nvim

### Search Keybindings

- `<leader>sf`: fuzzy files in the current working directory
- `<leader>sg`: grep text in the current working directory, literal mode by default
- `<leader>sG`: grep with prompts for search text, directories, include globs, and exclude globs
- `<leader>sw`: grep the current word, or the visual selection, in the current working directory
- `<leader>ss`: document symbols, preferring LSP and falling back to Treesitter
- `<leader>sS`: workspace symbols from LSP
- `<leader>sr`: resume the last Snacks picker

### Useful Picker Keys

- `<A-h>`: toggle hidden files
- `<A-i>`: toggle ignored files
- `<A-r>`: toggle regex mode
- `<C-q>`: send current results to quickfix
- `<C-s>`: open selection in a horizontal split
- `<C-v>`: open selection in a vertical split
- `<C-t>`: open selection in a new tab

## Neovim 0.12 Built-ins

- `v_an`: select the parent node, expanding outward
- `v_in`: select the child node, moving inward

## LSP Keybindings

- `gd`: go to definition
- `gh`: hover preview
- `gr`: list references with Snacks

## Notes

- `snacks.nvim` is managed by `vim.pack`.
- The pack lockfile is tracked in `nvim-pack-lock.json`.
- To add a plugin properly: add it to `vim.pack.add()` in `init.lua`, restart Neovim to install it, then review and commit the plugin spec plus `nvim-pack-lock.json`.
- To remove a plugin properly: delete its `vim.pack.add()` spec, restart Neovim, then run `:lua vim.pack.del({ 'plugin-name' })`.
