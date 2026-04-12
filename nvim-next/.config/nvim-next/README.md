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
- The built-in `catppuccin` colorscheme is the default theme.
- Search defaults to the current working directory, not the git root.
- `<leader>gg` opens Neogit for the current file's directory when possible, otherwise the current working directory.
- `<leader>gd` opens a repo review against the default branch and includes local changes.
- `<leader>gw` opens a working tree versus index diff for the current repo.
- Git diff signs appear in the sign column for added, changed, and deleted lines.
- `s` uses `flash.nvim` jump mode in normal, visual, and operator-pending modes.
- `<leader>er` runs `:Rex` to return to netrw explorer.
- `<leader>yr` copies the current line or visual line range as `path:start-end`.
- The statusline is a built-in custom one that shows file path, Git branch, and cursor position.
- Visible Neogit status buffers refresh automatically on idle and focus changes so external file edits show up without manual `<C-r>`.
- When the cwd is inside `~/dotfiles`, picker searches include hidden files and exclude `.git`.
- `<leader>sS` can reuse a compatible project LSP from another buffer, or bootstrap one from a hidden TS/JS project file when the current buffer itself has no attached LSP.
- `<leader>` shows available leader mappings with `which-key.nvim`.

## Snacks.nvim

### Search Keybindings

- `<Esc>`: clear search highlighting, including the automatic word highlight
- Idle on a word: highlight visible occurrences automatically; moving the cursor clears it
- `<leader>sf`: fuzzy files in the current working directory
- `<leader>sg`: grep text in the current working directory, literal mode by default
- `<leader>sG`: grep with prompts for search text, directories, include globs, and exclude globs
- `<leader>sw`: grep the current word, or the visual selection, in the current working directory
- `<leader>ss`: document symbols, preferring LSP and falling back to Treesitter
- `<leader>sS`: workspace symbols from LSP
- `<leader>sr`: resume the last Snacks picker

## Which-key.nvim

- `<leader>`: show available leader mappings
- `<leader>?`: show buffer-local keymaps on demand

## Colors

- The default theme is Neovim's built-in `catppuccin`
- `background=dark` uses Catppuccin Mocha
- `background=light` uses Catppuccin Latte

## Statusline

- Uses Neovim's built-in `statusline` option, not a plugin
- Left side shows `[branch +A,-D]` before the file path when inside a Git worktree
- The Git summary uses the same repo-wide add/delete counting style as the shell prompt
- When the repo is dirty but there are no add/delete line counts to show, it falls back to `x`
- Left side also shows the file path and buffer flags
- Right side shows `line:column`
- The old `All` text came from Neovim's default `'ruler'` display and is now replaced by the custom statusline

## Gitsigns.nvim

- Added, changed, and deleted lines show signs in the gutter
- Signs use simple text markers: `+`, `~`, `_`, and `‾`
- Inline blame is disabled for now to keep the gutter clean

## Flash.nvim

- `s`: jump to a visible target with labels
- `f`, `F`, `t`, `T`, `;`, and `,` use Flash's default enhanced character motions

## Clipboard

- `<leader>yr`: copy the current line or visual line range to the clipboard
- The copied format is repo-relative when inside a Git worktree
- Selecting the whole file copies only the relative path

## Neogit.nvim

- `<leader>gg`: open Git status
- `plenary.nvim` is installed because Neogit requires it
- `snacks.nvim` is enabled as Neogit's picker integration
- `diffview.nvim` is enabled as Neogit's diff viewer integration
- The status buffer auto-refreshes on `CursorHold` and `FocusGained` only while `NeogitStatus` is the current buffer

## Diffview.nvim

- `<leader>gd`: review the current branch against the default branch, including local changes
- `<leader>gw`: review the working tree against the index
- `<leader>gD`: close Diffview
- `<leader>gf`: file history for the current file
- `<leader>gF`: file history for the current repo
- The default-branch review resolves `origin/HEAD` first, then falls back to `origin/main`, `origin/master`, `main`, or `master`

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

- `snacks.nvim`, `which-key.nvim`, `gitsigns.nvim`, `plenary.nvim`, `neogit.nvim`, and `diffview.nvim` are managed by `vim.pack`.
- The pack lockfile is tracked in `nvim-pack-lock.json`.
- To add a plugin properly: add it to `vim.pack.add()` in `init.lua`, restart Neovim to install it, then review and commit the plugin spec plus `nvim-pack-lock.json`.
- To remove a plugin properly: delete its `vim.pack.add()` spec, restart Neovim, then run `:lua vim.pack.del({ 'plugin-name' })`.
