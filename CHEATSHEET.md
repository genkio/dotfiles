# Cheatsheet

Quick reference for all custom and built-in keybindings across tools.
Leader key is `<Space>` in Neovim. Tmux prefix is `C-j` or `C-f`.

---

## Custom

Everything below comes from personal configuration (commits to this repo).

### Zsh Aliases & Functions

| Alias / Fn | Expands To |
|---|---|
| `vi` / `vi <file>` | `nvim .` / `nvim <file>` |
| `cc` | `claude` |
| `cx` | `codex` |
| `lg` | `lazygit` |
| `ld` | `lazydocker` |
| `cl` | `clear` |
| `ls` | `eza --group-directories-first` |
| `ll` | `eza --group-directories-first --all -lh` |
| `lt` | `eza --group-directories-first --tree --level=2 --icons` |
| `ip` | `ipconfig getifaddr en0` |

**Tmux helpers**

| Command | What it does |
|---|---|
| `tx` | Attach or create default tmux session (`tmp`) |
| `tx <name>` | Attach to named session |
| `txp <profile>` | `tmuxp load -y <profile>` |
| `txl` | `tmux ls` |
| `ssh` | SSH with `TERM=xterm-256color` (wrapper) |
| `ssht <host>` | SSH + auto-attach tmux on remote |

**Git shortcuts**

| Alias / Fn | What it does |
|---|---|
| `gs` | `git status` |
| `glo` | `git log --pretty --oneline -5` |
| `gad` | `git add .` |
| `gco` | `git checkout` |
| `gbr` | 10 most recent branches with dates |
| `gst` | List staged file names |
| `gcm <msg>` | `git commit -m "<msg>"` |
| `gpl` | Pull current branch from origin |
| `gpu` | Push current branch to origin |
| `gpuf` | Force-push with lease |
| `gundo` | `git reset --soft HEAD~1` |

### Tmux

**Prefix: `C-j` or `C-f`**

| Key | Action |
|---|---|
| `prefix r` | Reload tmux config |
| `prefix w` | Prompt for name, create new window in current path |
| `prefix v` | Vertical split (side-by-side) in current path |
| `prefix h` | Horizontal split (top-bottom) in current path |
| `prefix x` | Kill pane (auto-rebalance) |
| `prefix X` | Kill all other panes in window |
| `prefix y` | Toggle synchronize-panes |
| `prefix T` | Set/edit pane label |
| `prefix P` | Open GitHub PR from pane label number (needs `GH_PR_BASE_URL`) |
| `C-z` | Toggle zoom (no prefix needed) |
| `C-h/j/k/l` | Navigate between panes (no prefix) |
| `S-Left / S-Right` | Previous / next window (no prefix) |
| `C-p / C-n` | Previous / next window (no prefix) |
| `C-S-Left / C-S-Right` | Reorder window left/right (no prefix) |

**Copy mode (vi keys)**

| Key | Action |
|---|---|
| `y` | Copy selection (stays in copy mode, OSC52) |
| `Enter` | Copy selection (stays in copy mode, OSC52) |
| Mouse drag | Copy on drag end (OSC52) |

### Ghostty

| Key | Action |
|---|---|
| `Cmd+k` | Next split |
| `Cmd+j` | Previous split |
| `Shift+Enter` | Insert newline (multi-line prompt) |

### Neovim - Custom Keymaps

**File navigation**

| Key | Action |
|---|---|
| `q` | Open netrw (file explorer) in current file's dir |
| `%` (in netrw) | Open fzf file picker with bat preview |

**Save & quit**

| Key | Action |
|---|---|
| `ZZ` | Save + format + close window (built-in vim) |
| `ZQ` | Close without saving (built-in vim) |
| `ZW` | Save without auto-format (custom) |

**Window navigation (tmux-safe)**

| Key | Action |
|---|---|
| `<leader>wh/j/k/l` | Focus left/down/up/right window |

**LSP (custom keymaps)**

| Key | Action |
|---|---|
| `gd` | Go to definition |
| `gh` | Hover (preview docs) |
| `gr` | List references (Telescope) |
| `<leader>rn` | Rename symbol |
| `<leader>rf` | Rename file (TypeScript, updates imports) |
| `<leader>ci` | Add missing imports |
| `<leader>co` | Organize imports |
| `<leader>ca` | Code action (imports/quickfix) |
| `<leader>dv` | Definition in vertical split |
| `<leader>dh` | Definition in horizontal split |

**Copy range**

| Key | Action |
|---|---|
| `<leader>yr` | Copy file path + line range to clipboard (normal & visual) |

**Escape alternative**

| Key | Action |
|---|---|
| `jk` | Exit insert mode (useful in browser terminals / ttyd) |

### Neovim - Custom Plugins

**Aerial (code outline)**

| Key | Action |
|---|---|
| `<leader>a` | Open floating code outline |
| `<leader>so` | Search outline symbols (Telescope) |
| `{` / `}` | Jump to prev/next symbol |
| Inside Aerial: `<CR>` | Jump to symbol |
| Inside Aerial: `C-v` / `C-s` | Jump in vsplit / hsplit |
| Inside Aerial: `o` | Toggle tree node |
| Inside Aerial: `q` | Close Aerial |

**Auto-session**

Sessions auto-save on exit and auto-restore per directory when opening `nvim` with no arguments.

| Command | Action |
|---|---|
| `:SessionSave` | Manually save session |
| `:SessionRestore` | Manually restore session |
| `:SessionDelete` | Delete session for cwd |
| `:Autosession search` | Search and load a session |
| `:Autosession delete` | Search and delete a session |

**Autotag** - Auto-closes and auto-renames HTML/XML tags in insert mode.

**LazyGit**

| Key | Action |
|---|---|
| `<leader>lg` | Open LazyGit |

**Diffview (PR diff / history)**

| Key | Action |
|---|---|
| `<leader>gd` | Open `DiffviewOpen origin/HEAD...HEAD --imply-local` (merge-base PR diff; local/LSP side swapped to left) |
| `<leader>gD` | Close Diffview |
| `<leader>gf` | File history for current file |
| `<leader>gF` | File history for repo |

**Snacks GitHub (PR / Issues picker)**

| Key | Action |
|---|---|
| `<leader>gi` | GitHub issues (open) |
| `<leader>gI` | GitHub issues (all) |
| `<leader>gp` | GitHub pull requests (open) |
| `<leader>gP` | GitHub pull requests (all) |
| `<leader>gr` | Resume last GitHub picker |
| `<leader>gR` | Resume last GitHub diff |
| In diff preview: `o` | Jump to file at diff line |
| In diff preview: `a` | Add diff comment |
| `C-w l` | Focus diff preview pane |
| `C-w w` | Cycle back to list |

**Gitsigns (extended config)**

Inline blame is ON by default (current line).

| Key | Action |
|---|---|
| `]c` / `[c` | Next / previous git hunk |
| `<leader>hs` | Stage hunk (normal + visual) |
| `<leader>hr` | Reset hunk (normal + visual) |
| `<leader>hS` | Stage entire buffer |
| `<leader>hu` | Undo stage hunk |
| `<leader>hR` | Reset entire buffer |
| `<leader>hp` | Preview hunk |
| `<leader>hb` | Blame current line |
| `<leader>hB` | Blame current line (full commit) |
| `<leader>hd` | Diff against index |
| `<leader>hD` | Diff against last commit |
| `<leader>hm` | Diff against main/master |
| `<leader>tb` | Toggle inline blame |
| `<leader>tD` | Toggle deleted lines preview |

**Other custom behaviors**

- Hyphenated words treated as one word (`ciw` on `<some-component>`) in HTML/JSX/TSX/Vue/Svelte
- OSC52 clipboard: yanking auto-copies over SSH and tmux via nvim-osc52
- Telescope searches from git root; includes hidden files in `~/dotfiles`
- Live grep defaults to fixed-string (`-F`); use `<leader>sG` for regex, `<leader>sa` for raw rg args

### Neovim - Custom Telescope grep tips

| Key (in live grep args picker) | Action |
|---|---|
| `C-k` | Toggle quoting around prompt |
| `C-f` | Insert `--glob ` flag for file filtering |

Example raw args: `myFunction --glob 'packages/backend/**'`

---

## Out-of-the-Box (Kickstart.nvim)

Features that come with the kickstart base config. You might not remember these exist.

### Vim Options Worth Knowing

| Setting | What it does |
|---|---|
| Relative line numbers | Enabled - jump with `5j`, `12k`, etc. |
| `inccommand = 'split'` | Live preview of `:s/old/new/g` substitutions in a split |
| `scrolloff = 10` | Cursor stays 10 lines from edge when scrolling |
| `confirm` | Prompts to save instead of erroring on `:q` with unsaved changes |
| `undofile` | Undo history persists across sessions |
| `clipboard = 'unnamedplus'` | Yank syncs to OS clipboard (local only, not over SSH) |
| Treesitter folding | `zc`/`zo`/`za` to fold/unfold code blocks (starts open) |
| Whitespace chars | Tabs shown as `>>`, trailing spaces as `*`, nbsp as `_` |

### Which-Key

Press any prefix key and **wait** - a popup shows all available continuations. Instant discovery of keymaps you forgot.

| Key | What it shows |
|---|---|
| `<leader>` then wait | All leader keymaps grouped by category |
| `<leader>s` | All **[S]earch** commands |
| `<leader>t` | All **[T]oggle** commands |
| `<leader>h` | All **Git [H]unk** commands |

### Telescope (Fuzzy Finder)

| Key | Action |
|---|---|
| `<leader>sf` | Find files |
| `<leader>sg` | Live grep (fixed-string) |
| `<leader>sG` | Live grep (regex) |
| `<leader>sa` | Live grep with raw rg args |
| `<leader>sw` | Grep current word under cursor |
| `<leader>sh` | Search help tags |
| `<leader>sk` | Search all keymaps |
| `<leader>ss` | Search Telescope builtins themselves |
| `<leader>sd` | Search diagnostics |
| `<leader>sr` | Resume last search |
| `<leader>s.` | Recent files |
| `<leader>sn` | Search Neovim config files |
| `<leader>s/` | Grep only in open files |
| `<leader>/` | Fuzzy find in current buffer |
| `<leader><leader>` | Switch between open buffers |

**Inside any Telescope picker:**

| Key | Action |
|---|---|
| `C-/` (insert mode) | Show picker keymaps help |
| `?` (normal mode) | Show picker keymaps help |
| `C-n` / `C-p` | Next / previous result |
| `<Esc>` | Close picker |

### LSP (Kickstart defaults)

These are set when an LSP attaches to a buffer:

| Key | Action |
|---|---|
| `grn` | Rename symbol |
| `gra` | Code action (normal + visual) |
| `grr` | Find references (Telescope) |
| `gri` | Go to implementation (Telescope) |
| `grd` | Go to definition (Telescope) |
| `grD` | Go to declaration |
| `grt` | Go to type definition |
| `gO` | Document symbols (Telescope) |
| `gW` | Workspace symbols (Telescope) |
| `<leader>th` | Toggle inlay hints |
| `<leader>q` | Open diagnostic quickfix list |

LSP also auto-highlights all references of the symbol under your cursor after a short pause.

### Autoformat (Conform)

| Key | Action |
|---|---|
| `<leader>f` | Format buffer manually |
| (on save) | Auto-formats on save (Lua: stylua, JS/TS/JSX/TSX: prettier) |

Disable auto-format temporarily with `ZW` (custom) or set `vim.g.disable_autoformat = true`.

### Autocompletion (Blink.cmp)

Preset: **enter** to accept.

| Key | Action |
|---|---|
| `<Enter>` | Accept completion |
| `<C-space>` | Open completion menu / toggle docs |
| `<C-n>` / `<C-p>` | Next / previous suggestion |
| `<C-e>` | Dismiss menu |
| `<C-k>` | Toggle signature help |
| `<Tab>` / `<S-Tab>` | Jump to next/prev snippet placeholder |

Signature help auto-shows while typing function arguments.

### Mini.nvim

**Surround** (`sa` / `sd` / `sr`)

| Key | Action | Example |
|---|---|---|
| `saiw)` | Surround word with parens | `hello` -> `(hello)` |
| `sa2w"` | Surround 2 words with quotes | `hello world` -> `"hello world"` |
| `sd"` | Delete surrounding quotes | `"hello"` -> `hello` |
| `sr)"` | Replace `()` with `""` | `(hello)` -> `"hello"` |
| `sf)` | Find next `)` surround | |
| `sF)` | Find previous `)` surround | |

**AI textobjects** (better around/inside)

Works with any operator (`d`, `c`, `y`, `v`, etc.):

| Key | Selects |
|---|---|
| `va)` / `vi)` | Around/inside parentheses |
| `va"` / `vi"` | Around/inside quotes |
| `vaf` / `vif` | Around/inside function call |
| `vaa` / `via` | Around/inside argument |
| `vab` / `vib` | Around/inside brackets |
| `vat` / `vit` | Around/inside tags |

### Todo Comments

Highlights `TODO`, `FIXME`, `HACK`, `WARN`, `NOTE`, `PERF` in comments. Search them with `:TodoTelescope`.

### Treesitter

- Syntax highlighting for all auto-installed languages
- Better code folding (`zc`/`zo`/`za`)
- Powers aerial code outline, autotag, and textobjects

### Other Built-in Keymaps

| Key | Action |
|---|---|
| `<Esc>` | Clear search highlights |
| `<Esc><Esc>` (terminal) | Exit terminal mode |
| `<C-h/j/k/l>` | Navigate between splits |
| `yap` | Yank a paragraph (highlights on yank) |

### Plugin Management (Lazy.nvim)

| Command | Action |
|---|---|
| `:Lazy` | Open plugin manager UI |
| `:Lazy update` | Update all plugins |
| `:Mason` | Open LSP/tool installer UI |
