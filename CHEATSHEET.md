# Cheatsheet

Quick reference for the custom and notable keybindings across tools.
Leader key is `<Space>` in Neovim. Tmux prefix is `C-j` or `C-f`.

Everything here comes from this repo's configuration. For the full Neovim
behavior reference see `nvim/.config/nvim/README.md`.

---

## Zsh Aliases & Functions

| Alias / Fn | What it does |
|---|---|
| `vi` / `vi <file>` | `nvim .` / `nvim <file>` |
| `y` | `yazi` |
| `cc` | `claude`; `cc <text>` starts Claude with that prompt; `cc -<flag>` passes flags through |
| `ccx` | `claude --dangerously-skip-permissions` |
| `cx` | `codex` |
| `lg` | Open LazyGit (inside a throwaway nvim; `Q` quits back to the shell) |
| `ld` | `lazydocker` |
| `dropbox` | `maestral` |
| `x` | `clear` |
| `xx` | `exit` |
| `ff` | `fastfetch` |
| `ls` | `eza --group-directories-first` |
| `ll` | `eza --group-directories-first --all -lh` |
| `lt` | `eza --group-directories-first --tree --level=2 --icons` |
| `lti` | `eza --group-directories-first --all --tree --icons` |
| `ip` | `ipconfig getifaddr en0` |
| `cp1` | Copy the last command to clipboard |
| `src` | `source ~/.zshrc` |
| `his` | Open `~/.zsh_history` |
| `zip <path>` | Zip a file/folder via 7-Zip (no compression), strip macOS metadata, move source to Trash |
| `unzip <path>` | Extract a `.zip` next to itself; on a folder, extract every `.zip` inside it |
| `killport <port>` / `kip <port>` | TERM whatever process is listening on the given TCP port |
| `ltail <path>` | `lnav <path>` (log navigator) |
| `vmise` | Convert `package.json`'s `volta` versions into a `mise use` invocation |

**Tmux helpers**

| Command | What it does |
|---|---|
| `tx` | Attach or create default tmux session (`tmp`) |
| `tx <name>` | Attach to or create a named session |
| `txk [name]` | Kill named session, defaulting to `tmp` |
| `txp <profile>` | `tmuxp load -y <profile>` |
| `txl` | `tmux ls` |

**Tailscale helpers**

| Command | What it does |
|---|---|
| `fsend <machine> <file...>` | Send files with Tailscale file transfer |
| `fget [dir]` | Pull waiting Tailscale files into `dir` or `~/Downloads/` |

**Git shortcuts**

| Alias / Fn | What it does |
|---|---|
| `gs` | `git status` |
| `gst` / `gstp` | `git stash` / `git stash pop` |
| `glo` | `git log --pretty --oneline -5` |
| `ga` / `gaa` | `git add` / `git add .` |
| `gau` | `git restore --staged .` |
| `gd` | `git diff` |
| `gco` | `git checkout` |
| `gcof` | `git checkout -f && git clean -df` |
| `gcom` | Checkout the `origin` default branch |
| `grb` | Rebase onto the `origin` default branch |
| `gbr` | 10 most recent branches with dates |
| `gcm <msg>` | `git commit -m "<msg>"` |
| `gpl` / `gpu` | Pull / push the current branch from/to origin |
| `gpuf` | Force-push current branch with lease |
| `gundo` | `git reset --soft HEAD~1` (undo last commit, keep changes staged) |
| `gdc <commit>` | Copy a commit's diff to the clipboard |
| `gtreea [branch]` | Add a worktree tracking a remote branch (fzf-picks one if omitted), then `cd` in |
| `gtreen [branch]` | Add a worktree on a new branch off the default branch, then `cd` in |
| `gtreer [branch]` | Remove a worktree (fzf-picks one if omitted) and delete its branch, after confirmation |

---

## Tmux

**Prefix: `C-j` or `C-f`**

| Key | Action |
|---|---|
| `prefix r` | Reload tmux config |
| `prefix c` | Prompt for name, create new window in current path |
| `prefix w` | Choose a window from a tree |
| `prefix v` | Vertical split (side-by-side) in current path |
| `prefix h` | Horizontal split (top-bottom) in current path |
| `prefix x` | Kill pane (auto-rebalance) |
| `prefix X` | Kill all other panes in window |
| `prefix y` | Toggle synchronize-panes |
| `prefix T` | Set/edit pane label |
| `prefix P` | Copy the first number found in the pane label to clipboard |
| `prefix C-s` / `prefix C-r` | Save / restore tmux state (`tmux-resurrect`) |
| `prefix I` | Install tmux plugins (`tpm`) |
| `prefix q` | Show pane index numbers (press a number to jump) |

**No prefix needed**

| Key | Action |
|---|---|
| `C-z` / `C-Up` | Toggle pane zoom |
| `C-h/j/k/l` | Navigate between panes |
| `C-Down` | Choose a window from a tree (same as `prefix w`) |
| `S-Left` / `S-Right` | Previous / next window |
| `C-p` / `C-n` | Previous / next window |
| `C-S-Left` / `C-S-Right` | Reorder window left / right |
| `M-1` .. `M-9` | Jump to window 1-9 |
| `M-0` | Jump to the highest-numbered window |
| `C-/` (or `C-_`) | Toggle copy-mode |

Plugins (via TPM): `tmux-resurrect`, `genkio/tmux-open-usage` (disabled by default), `genkio/tmux-spoony`. Resurrect captures pane contents; save/restore is manual via `prefix C-s` / `prefix C-r`.

**Copy mode (vi keys)**

| Key | Action |
|---|---|
| `y` | Copy selection (stays in copy mode, OSC52) |
| `Enter` | Copy selection (stays in copy mode, OSC52) |
| Mouse drag | Copy on drag end (OSC52) |

---

## Alacritty

Primary terminal: transparent titlebar, OSC52 clipboard, `option`-as-`alt`.

| Key | Action |
|---|---|
| `Shift+Enter` | Insert newline (multi-line prompt) |
| `Cmd+Shift+Space` | Toggle vi mode |

Theme: `Flexoki Light` / `TokyoNight Storm` palettes. Alacritty can't read macOS appearance itself, so the light/dark switch is driven by the Hammerspoon appearance watcher and `theme-toggle.sh`, which rewrite `~/.cache/dotfiles/alacritty-theme-active.toml` (Alacritty reloads it live). No splits/tabs - use tmux.

---

## Neovim

Neovim 0.12, launched with `nvim`. Plugins (via native `vim.pack`): `flexoki-nvim`, `tokyonight.nvim`, `flash.nvim`, `snacks.nvim`, `which-key.nvim`, `gitsigns.nvim`. LSP is core `vim.lsp` (`ts_ls`), no plugin manager UI. The file explorer is netrw; pickers and grep are Snacks.

### File explorer (netrw)

| Key | Action |
|---|---|
| `<CR>` (on dir) | Expand / collapse the directory inline (tree view) |
| `<CR>` (on file) | Open it; closes the preview window if one was open |
| `p` | Preview the file while keeping focus in netrw (auto-updates as the cursor moves) |
| `q` | Close the preview window |
| `<leader>er` | Return to the explorer and reveal the current file (reopens netrw at cwd after a restart) |

### Search & pickers (Snacks)

| Key | Action |
|---|---|
| `<leader>sf` | Find files in cwd |
| `<leader>sg` | Grep text in cwd (literal/fixed-string) |
| `<leader>sG` | Grep with prompts for text, dirs, include globs, exclude globs (`-w` word match) |
| `<leader>sw` | Grep the word under cursor / visual selection in the **current file** |
| `<leader>sW` | Grep the word under cursor / visual selection in **cwd** |
| `<leader>ss` | Document symbols (LSP, falls back to Treesitter) |
| `<leader>sS` | Workspace symbols (LSP; can bootstrap a client from a hidden project file) |
| `<leader>sr` | Resume the last Snacks picker |

Inside a Snacks picker (defaults): `<A-h>` toggle hidden, `<A-i>` toggle ignored, `<A-r>` toggle regex, `<C-q>` send to quickfix, `<C-s>` open in hsplit, `<C-v>` open in vsplit, `<C-t>` open in tab.
When cwd is inside `~/dotfiles`, picker searches include hidden files and exclude `.git`.

### LSP

Set when an LSP attaches (outside vault markdown buffers):

| Key | Action |
|---|---|
| `gd` | Go to definition |
| `gh` | Hover (preview docs) |
| `gr` | List references (Snacks picker) |
| `<leader>xl` | Buffer diagnostics in the location list |
| `<leader>xx` | Workspace diagnostics in the quickfix list |

### Git (Gitsigns) & LazyGit

Inline blame is OFF by default. Signs: `+` add, `~` change, `_` delete.

| Key | Action |
|---|---|
| `]c` / `[c` | Next / previous git hunk (built-in diff-change nav inside a diff) |
| `<leader>gp` | Preview the current hunk |
| `<leader>gb` | Blame the current line |
| `<leader>gB` | Open the GitHub PR for the blamed line's commit (needs `gh`) |
| `<leader>lg` | Open LazyGit (default layout, command log hidden) |
| `<leader>lG` | Open LazyGit (compact layout for small screens) |
| `:LazyGit` | Open LazyGit (default layout) |

### Motion & jumps (Flash)

| Key | Action |
|---|---|
| `s` | Flash jump to a visible target (normal, visual, operator-pending). Press `s`, type 1-2 chars of the target, then the shown label |
| `f` / `F` / `t` / `T` / `;` / `,` | Flash's enhanced character motions |

In Markdown and plain-text buffers (which wrap), `j` / `k` / `$` / `^` move by **display line**. A count moves by logical line (`5j`), and operator-pending motions stay logical (`dj`, `d$`).

### Markdown vault navigation

Inside Markdown files in an Obsidian/Logseq-style vault (detected by `.obsidian/` or `logseq/config.edn`):

| Key | Action |
|---|---|
| `gd` on `[[note]]` | Open the linked note, or create it in the vault's new-note folder if missing |
| `gd` on `#tag` | Open a matching tag page if one exists; otherwise search that tag |
| `gr` on a note | Search backlinks to the current note |
| `gr` on `#tag` | Search references to that tag |
| Type `[[` | Omni completion for linkable notes |
| Type `#` | Omni completion for known tags |
| `<Tab>` | Insert two spaces |

### Editing helpers

| Key | Action |
|---|---|
| `<leader>yr` | Copy file path + line range to clipboard, `$HOME`-relative (normal & visual) |
| `Q` | Quit all windows (prompts to save/discard on unsaved changes) |
| `<Esc>` | Clear search highlight and the automatic cursor-word highlight |
| `zc` / `zo` (JSON/JSONC) | Close / open the `{`...`}` or `[`...`]` block under the cursor |
| `<leader>` then wait | Which-key popup of leader mappings (groups: Explorer, Git, LazyGit, Search, Diagnostics, Yank) |
| `<leader>?` | Show buffer-local keymaps |

### Automatic behaviors

- **Directory resume**: `nvim .` reopens the last real file you had focused in that directory.
- **Auto-save**: markdown / plain-text buffers auto-save on `InsertLeave`, `TextChanged`, `FocusLost`, but only when launched with a single file argument (e.g. `vi ~/notes/draft.md`). Bare `vi` and `vi some/folder/` leave it off.
- **Auto-reload**: files changed on disk reload automatically (notifies on reload).
- **Restore cursor**: reopening a file restores the last cursor position.
- **Cursor-word highlight**: idling on a word highlights its visible occurrences; moving the cursor clears it.
- **Yank highlight**: yanked text flashes briefly.
- **Theme follows macOS**: Flexoki Light (light) / TokyoNight Storm (dark), re-checked on focus.

### Vim options worth knowing

| Setting | What it does |
|---|---|
| Relative + absolute line numbers | Jump with `5j`, `12k`; current line shows its absolute number |
| `inccommand = 'split'` | Live preview of `:s/old/new/g` in a split |
| `scrolloff = 10` | Cursor stays 10 lines from the edge |
| `confirm` | Prompts to save instead of erroring on `:q` with unsaved changes |
| `undofile` | Undo history persists across sessions |
| `clipboard = 'unnamedplus'` | Yank syncs to the OS clipboard locally; over SSH it uses OSC52 (the `osc52-copy.sh` helper inside tmux, the built-in provider otherwise) |
| `signcolumn = 'yes'` | Gutter always present so it does not jump |
| `ignorecase` + `smartcase` | Case-insensitive search unless the pattern has uppercase |
| `iskeyword += '-'` | Hyphenated words count as one word (`ciw` on `<some-component>`); prose buffers (markdown/text) treat `-` as a word boundary instead |
| Whitespace | Trailing spaces shown as `+` |

### Neovim 0.12 built-ins

| Key | Action |
|---|---|
| `v_an` | Select the parent Treesitter node (expand outward) |
| `v_in` | Select the child Treesitter node (move inward) |
| `gcc` / `gc{motion}` | Toggle line comment (current line, or over a motion like `gcip`) |
| `gc` (visual) | Toggle comment on the selection |
| `<C-x><C-o>` | Omni completion (used for `[[note]]` / `#tag` in vaults) |
