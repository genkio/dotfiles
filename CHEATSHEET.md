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
| `y` | `yazi` |
| `cc` | `claude` |
| `cx` | `codex` |
| `cct` | Run Claude with `claude-trace` |
| `lg` | `lazygit` |
| `ld` | `lazydocker` |
| `cl` | `clear` |
| `ex` | `exit` |
| `ff` | `fastfetch` |
| `ls` | `eza --group-directories-first` |
| `ll` | `eza --group-directories-first --all -lh` |
| `lt` | `eza --group-directories-first --tree --level=2 --icons` |
| `lti` | `eza --group-directories-first --all --tree --icons` |
| `ip` | `ipconfig getifaddr en0` |
| `cp1` | Copy the last command to clipboard |
| `src` | `source ~/.zshrc` |
| `vrc` | Open `~/.zshrc` |
| `vhi` | Open `~/.zsh_history` |
| `vrca` | Open `~/.zsh_aliases` |

**Tmux helpers**

| Command | What it does |
|---|---|
| `tx` | Attach or create default tmux session (`tmp`) |
| `tx <name>` | Attach to named session |
| `txk [name]` | Kill named session, defaulting to `tmp` |
| `txp <profile>` | `tmuxp load -y <profile>` |
| `txl` | `tmux ls` |
| `ssht <host>` | SSH + auto-attach tmux on remote |

**Tailscale helpers**

| Command | What it does |
|---|---|
| `fsend <machine> <file...>` | Send files with Tailscale file transfer |
| `fget [dir]` | Pull waiting Tailscale files into `dir` or `~/Downloads/` |

**Git shortcuts**

| Alias / Fn | What it does |
|---|---|
| `gs` | `git status` |
| `gst` | `git stash` |
| `gstp` | `git stash pop` |
| `glo` | `git log --pretty --oneline -5` |
| `ga` | `git add` |
| `gaa` | `git add .` |
| `gau` | `git restore --staged .` |
| `gd` | `git diff` |
| `gco` | `git checkout` |
| `gcof` | `git checkout -f && git clean -df` |
| `gcom` | Checkout the `origin` default branch |
| `grb` | Rebase onto the `origin` default branch |
| `gbr` | 10 most recent branches with dates |
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
| `prefix c` | Prompt for name, create new window in current path |
| `prefix w` | Show list of windows of the current session |
| `prefix v` | Vertical split (side-by-side) in current path |
| `prefix h` | Horizontal split (top-bottom) in current path |
| `prefix x` | Kill pane (auto-rebalance) |
| `prefix X` | Kill all other panes in window |
| `prefix y` | Toggle synchronize-panes |
| `prefix T` | Set/edit pane label |
| `prefix P` | Open GitHub PR from pane label number (needs `GH_PR_BASE_URL`) |
| `prefix C-s` | Save tmux state (`tmux-resurrect`) |
| `prefix C-r` | Restore tmux state (`tmux-resurrect`) |
| `prefix I` | Install tmux plugins (`tpm`) |
| `prefix q` | Show pane index numbers (press a number to jump to that pane) |
| `C-z` | Toggle zoom (no prefix needed) |
| `C-h/j/k/l` | Navigate between panes (no prefix) |
| `S-Left / S-Right` | Previous / next window (no prefix) |
| `C-p / C-n` | Previous / next window (no prefix) |
| `C-S-Left / C-S-Right` | Reorder window left/right (no prefix) |

`tmux-continuum` auto-saves in the background and auto-restores on tmux server start.

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

Ghostty shell integration enables `sudo`, `ssh-terminfo`, and `ssh-env` so SSH prefers `xterm-ghostty` when the remote host can support it and falls back cleanly when it cannot.

### Neovim - Custom Keymaps

**File navigation**

| Key | Action |
|---|---|
| `q` | Open Yazi at Git root and reveal current file (falls back to current dir outside Git) |
| `<leader>cw` | Open Yazi in Neovim's current working directory |

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
| `gO` | Search symbols in current file (Telescope document symbols) |
| `gW` | Search symbols across workspace/project (Telescope workspace symbols) |
| `<leader>rn` | Rename symbol |
| `<leader>rf` | Rename file (TypeScript, updates imports) |
| `<leader>ci` | Add missing imports |
| `<leader>co` | Organize imports |
| `<leader>ca` | Code action (imports/quickfix) |
| `<leader>dv` | Definition in vertical split |
| `<leader>dh` | Definition in horizontal split |

**Markdown vault navigation**

Inside Markdown files that live in an Obsidian/Logseq-style vault (detected by `.obsidian/` or `logseq/config.edn`), `gd` and `gr` are repurposed for note navigation:

| Key | Action |
|---|---|
| `gd` on `[[note]]` | Open the linked note, or create it in the vault's configured new-note folder if missing |
| `gd` on `#tag` | Open a matching tag page if one exists; otherwise search that tag in the current vault |
| `gr` on a note page | Search backlinks to the current note in the current vault |
| `gr` on `#tag` | Search references to that tag in the current vault |
| Type `[[` | Open completion for linkable notes in the current vault |
| Type `#` | Open completion for known tags in the current vault |
| `Tab` | Insert two spaces |

**Copy range**

| Key | Action |
|---|---|
| `<leader>yr` | Copy file path + line range to clipboard (normal & visual) |

**Escape alternative**

| Key | Action |
|---|---|
| `jk` | Exit insert mode (useful in browser terminals / ttyd) |

### Neovim - Custom Plugins

**Auto-session**

Sessions auto-save on exit and auto-restore per directory when opening `nvim` with no arguments.

| Command | Action |
|---|---|
| `:SessionSave` | Manually save session |
| `:SessionRestore` | Manually restore session |
| `:SessionDelete` | Delete session for cwd |
| `:Autosession search` | Search and load a session |
| `:Autosession delete` | Search and delete a session |

**Flash**

| Key | Action |
|---|---|
| `s` | Jump to visible text in normal, visual, or operator-pending mode |

Usage: press `s`, type one or two characters from the target, then press the label shown on screen. This replaces Vim's built-in `s` substitute mapping.

**LazyGit**

| Key | Action |
|---|---|
| `<leader>lg` | Open LazyGit |

**Yazi (file manager)**

| Key | Action |
|---|---|
| `q` | Open Yazi at Git root and reveal current file |
| `<leader>cw` | Open Yazi in current working directory |
| `z` (inside Yazi) | Fuzzy find from Git root; outside Git, fuzzy find from current Yazi dir |
| `Z` (inside Yazi) | Jump to a recent directory via zoxide |
| `/` (inside Yazi) | Search filenames in current view |
| `f` (inside Yazi) | Filter files by name |
| `S` (inside Yazi) | Search file contents with ripgrep |
| `,` (inside Yazi) | Open sort options |
| `s` / `M` (inside sort options) | Sort by size / modified time (descending) |
| `c` (inside Yazi) | Open copy options |
| Status bar | Shows hovered file size in footer |
| Hidden files | Shown by default |
| `F1` (inside Yazi) | Show Yazi key help |
| `C-v` / `C-x` / `C-t` (inside Yazi) | Open selected file in vsplit / hsplit / tab |
| `C-q` (inside Yazi) | Send selected files to quickfix |
| `C-\` (inside Yazi) | Change Neovim cwd to Yazi's current directory |
| `Enter` (files pane) | Toggle the expansion or collapse of the selected directory |

On narrow UIs, Yazi switches to a mobile profile with a single main column.

**Neogit (Diffview / Review Helpers)**

| Key | Action |
|---|---|
| `d` then `m` | Open PR review diff against the repo default branch (`origin/HEAD`, or fallback `main` / `master`) |
| `V` | Enter visual-line mode in a hunk so `s` / `u` can stage or unstage selected rows instead of the whole chunk |
| `<Tab>` | Open the diff for the next file while staying in the diff panes |
| `<S-Tab>` | Open the diff for the previous file while staying in the diff panes |
| `<leader>e` | Focus the left file list pane |
| `gf` | Open the actual local file from Diffview without closing the review tab |
| `<leader>id` | Open a delta preview float for the current Diffview file |
| `<leader>ic` | Open the GitHub inline comment composer from Diffview |
| `<leader>ia` | Open the approve-PR composer from Diffview |
| visual `<leader>ie` | Open the LLM inline-send composer with selected code reference |
| normal `<leader>ie` | Open the LLM inline-send composer (or capture current Neogit diff line context) |
| `<leader>is` in float | Send the inline-send message to the sibling tmux pane |
| `<leader>ia` in review float | Approve the PR with the typed comment |
| `<C-s>` in review float | Submit the current review action |
| `q` / `<Esc>` in float | Cancel and close the inline composer |

With 2 tmux panes, inline-send auto-targets the other pane. With 3+, it shows a picker.

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
| `<leader>ho` | Open PR/commit for blamed line (GitHub: PR → commit fallback, Bitbucket: commit page) |
| `<leader>tb` | Toggle inline blame |
| `<leader>tD` | Toggle deleted lines preview |

**Other custom behaviors**

- Hyphenated words treated as one word (`ciw` on `<some-component>`) in HTML/JSX/TSX/Vue/Svelte
- OSC52 clipboard: over SSH inside tmux, yanking uses the `osc52-copy.sh` helper; outside tmux it uses Neovim's built-in OSC52 provider
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
| `clipboard = 'unnamedplus'` | Yank syncs to the OS clipboard locally; over SSH inside tmux it uses the OSC52 helper, otherwise it forces `g:clipboard = 'osc52'` |
| Folding | Manual folds are available with `zc`/`zo`/`za` (starts open) |
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

In markdown note vaults, formatting currently normalizes nested bullet indentation so a child list item is at most one indent level deeper than its parent list item.

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
