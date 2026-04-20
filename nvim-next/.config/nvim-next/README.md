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
- Prefer performance and responsiveness over novelty; if a feature adds noticeable lag, avoid adding it unless the payoff is unusually high
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
- Reopening a normal file restores the last cursor position from the `'"` mark.
- `updatetime` is set to `250ms` so `CursorHold`-based reloads feel responsive in tmux.
- `nvim .` reopens the last real file you had focused in that directory.
- TypeScript LSP is enabled through core Neovim 0.12 `vim.lsp` using `ts_ls`.
- The built-in `catppuccin` colorscheme is the default theme.
- Search defaults to the current working directory, not the git root.
- `<leader>lg` opens LazyGit in a new tab terminal with the default layout, but hides the command log pane.
- `<leader>lG` opens LazyGit in a new tab terminal with the compact layout.
- `<leader>gd` opens a repo review against the default branch and includes local changes.
- `<leader>gw` opens a working tree versus index diff for the current repo.
- Diffview loads on first use instead of at startup.
- `:!` shell commands can use zsh helper functions from your dotfiles.
- Git diff signs appear in the sign column for added, changed, and deleted lines.
- Trailing spaces are shown as `+`.
- `s` uses `flash.nvim` jump mode in normal, visual, and operator-pending modes.
- `<leader>er` runs `:Rex` to return to netrw explorer.
- `<leader>yr` copies the current line or visual line range as `path:start-end`.
- Inside Markdown files in Obsidian/Logseq-style vaults, `gd` and `gr` switch to note/tag navigation and search, and typing `[[` or `#` triggers built-in omni completion for vault notes or tags.
- The statusline is a built-in custom one that shows file path and cursor position.
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

### Picker Keys

- These apply inside Snacks pickers such as `<leader>sf`, `<leader>sg`, `<leader>ss`, and `<leader>sr`
- `<A-h>`: toggle hidden files
- `<A-i>`: toggle ignored files
- `<A-r>`: toggle regex mode
- `<C-q>`: send current results to quickfix
- `<C-s>`: open selection in a horizontal split
- `<C-v>`: open selection in a vertical split
- `<C-t>`: open selection in a new tab

## Which-key.nvim

- `<leader>`: show available leader mappings
- `<leader>?`: show buffer-local keymaps on demand

## LazyGit

- `<leader>lg`: open LazyGit with the default layout, but without the command log pane
- `<leader>lG`: open LazyGit with the compact laptop-oriented layout
- `:LazyGit`: open LazyGit with the default layout
- The compact launcher applies a small-screen layout override for LazyGit, including stacked half-screen mode and a more aggressive focused-side expansion
- If `delta` is installed, LazyGit uses it as the diff pager via a small launcher-specific override config

## Colors

- The default theme is Neovim's built-in `catppuccin`
- `background=dark` uses Catppuccin Mocha
- `background=light` uses Catppuccin Latte

## Statusline

- Uses Neovim's built-in `statusline` option, not a plugin
- Left side shows the file path
- Right side shows `line:column`
- The old `All` text came from Neovim's default `'ruler'` display and is gone because the custom statusline replaces it
- Buffer flag labels like `[RO]` and `[-]` are intentionally omitted

## Gitsigns.nvim

- Added, changed, and deleted lines show signs in the gutter
- Signs use simple text markers: `+`, `~`, `_`, and `‾`
- Inline blame is disabled for now to keep the gutter clean
- `gc` and `gC`: jump to the next or previous hunk
- `<leader>gp`: preview the current hunk
- `<leader>gb`: show Git blame for the current line
- `<leader>gB`: open the GitHub PR associated with the blamed line's commit (requires `gh`)

## Flash.nvim

- `s`: jump to a visible target with labels
- `f`, `F`, `t`, `T`, `;`, and `,` use Flash's default enhanced character motions

## Clipboard

- `<leader>yr`: copy the current line or visual line range to the clipboard
- The copied format is repo-relative when inside a Git worktree
- Selecting the whole file copies only the relative path

## Markdown Vault Navigation

- Vault roots are detected by `.obsidian/` or `logseq/config.edn`
- `gd` on `[[note]]`: open the linked note, or create it in the vault's configured new-note folder if it does not exist
- `gd` on `#tag`: open a matching tag page if one exists; otherwise search that tag in the current vault
- `gr` on `#tag`: search references to that tag in the current vault
- `gr` elsewhere on a vault note: search backlinks to the current note in the current vault
- Typing `[[` triggers built-in omni completion for linkable notes in the current vault without pre-filling the first match
- Typing `#` at a tag boundary triggers built-in omni completion for known vault tags without pre-filling the first match
- `<Tab>` inserts two spaces in vault markdown buffers

## Netrw

- Tree listing is the default netrw view
- In tree view, `<CR>` on a directory expands or collapses it inline
- If a preview window is open, `<CR>` on a real file opens it and closes the preview automatically
- `p` previews the file in a preview window while keeping focus in netrw
- Once a preview window is open, moving the cursor in netrw auto-updates the preview for files under the cursor
- `q` closes the preview window
- `<leader>er` returns to the previous explorer when netrw has return state
- After a restart, `<leader>er` reopens netrw at the current working directory and expands the current file's directory path when possible

## Diffview.nvim

- `plenary.nvim` is installed because Diffview requires it
- `<leader>gd`: review the current branch against the default branch, including local changes
- `<leader>gw`: review the working tree against the index
- `<leader>gD`: close Diffview
- `<leader>gf`: file history for the current file
- `<leader>gF`: file history for the current repo
- Diffview is loaded on first use
- The default-branch review resolves `origin/HEAD` first, then falls back to `origin/main`, `origin/master`, `main`, or `master`

## Neovim 0.12 Built-ins

- `v_an`: select the parent node, expanding outward
- `v_in`: select the child node, moving inward

## LSP Keybindings

- `gd`: go to definition outside vault markdown buffers
- `gh`: hover preview
- `gr`: list references with Snacks outside vault markdown buffers
- `<leader>xl`: open the current buffer diagnostics in the location list
- `<leader>xx`: open workspace diagnostics in the quickfix list

## Notes

- `snacks.nvim`, `which-key.nvim`, `gitsigns.nvim`, `plenary.nvim`, and `diffview.nvim` are managed by `vim.pack`.
- The pack lockfile is tracked in `nvim-pack-lock.json`.
- To add a plugin properly: add it to `vim.pack.add()` in `init.lua`, restart Neovim to install it, then review and commit the plugin spec plus `nvim-pack-lock.json`.
- To remove a plugin properly: delete its `vim.pack.add()` spec, restart Neovim, then run `:lua vim.pack.del({ 'plugin-name' })`.
- If a removed plugin still shows up in `nvim-pack-lock.json`, do not edit the lockfile by hand. It usually means the plugin still exists on disk; clean it up with `:lua vim.pack.del({ 'plugin-name' })`.
