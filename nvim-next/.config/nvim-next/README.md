# nvim-next

Clean Neovim 0.12 sandbox launched with:

```sh
NVIM_APPNAME=nvim-next nvim
```

`<leader>` is `Space`.

## Session Prompt

- Work in `nvim-next/.config/nvim-next` as a clean Neovim 0.12 config
- Check latest Neovim 0.12 / official docs first for every task
- Prefer built-in Neovim features when possible
- If built-in is enough, explain how to use it; if config is needed, implement it in `nvim-next`
- Use `nvim/.config/nvim` only as reference when I say "previously"
- Keep `nvim-next` minimal, stable, and pragmatic
- Prefer small local Lua modules over plugin-heavy setups
- Only add a plugin when it is clearly justified; configure only the needed part
- Avoid complex or brittle custom logic for small gains
- For high-value workflow improvements with no clean built-in solution, small isolated custom logic is acceptable if it is low-risk, easy to remove, and clearly scoped to one module
- If a requirement is too complex or intrusive even under that bar, keep the simpler behavior instead
- If a customization fights Neovim/plugin defaults and becomes unstable, prefer removing it over layering more fixes
- Update README/docs when behavior changes meaningfully
- Verify changes when possible

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
- Neogit's built-in `auto_refresh` is enabled, but its `.git` filewatcher is disabled.
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
- Left side shows the branch segment, repo-wide Git summary, and file path
- Right side shows `line:column`
- The old `All` text came from Neovim's default `'ruler'` display and is gone because the custom statusline replaces it
- Buffer flag labels like `[RO]` and `[-]` are intentionally omitted

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

## Netrw

- Tree listing is the default netrw view
- In tree view, `<CR>` on a directory expands or collapses it inline
- If a preview window is open, `<CR>` on a real file opens it and closes the preview automatically
- `p` previews the file in a preview window while keeping focus in netrw
- Once a preview window is open, moving the cursor in netrw auto-updates the preview for files under the cursor
- `q` closes the preview window
- `<leader>er` runs `:Rex` to return to the explorer

## Neogit.nvim

- `<leader>gg`: open Git status
- `plenary.nvim` is installed because Neogit requires it
- `snacks.nvim` is enabled as Neogit's picker integration
- `diffview.nvim` is enabled as Neogit's diff viewer integration
- Neogit's built-in `auto_refresh` is enabled
- Neogit's `.git` filewatcher is disabled
- In `NeogitStatus`, `<CR>` is remapped to Neogit's `TabOpen` action so closing the file returns you to status
- Use `<C-r>` in the status buffer whenever you want a manual refresh

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
