# Cheatsheet

Quick reference for the custom and notable keybindings across tools.
Leader key is `<Space>` in Neovim. Tmux prefix is `C-j` or `C-f`.

Everything here comes from this repo's configuration. For the full Neovim
behavior reference see `nvim/.config/nvim/README.md`.

`CHEATSHEET-tmux-alacritty.html` is a standalone, printable version of the Tmux
and Alacritty sections below. It also spells out the stock tmux defaults this
file leaves out, so it reads on its own without knowing this config.

---

## Zsh Aliases & Functions

| Alias / Fn | What it does |
|---|---|
| `vi` / `vi <file>` | `nvim .` / `nvim <file>` |
| `y` | `yazi` |
| `cc` | `claude`; `cc <text>` starts Claude with that prompt; `cc -<flag>` passes flags through; `cc -eh/-ex/-em` = `--effort high/xhigh/max` |
| `ccx` | `claude --dangerously-skip-permissions` |
| `ccf` / `cco` | `cc` on Fable 5.1 / the same plus the orchestrator system prompt (`cc -o`, which dispatches herdlet workers) |
| `cx` / `cxx` | `codex` / `codex --dangerously-bypass-approvals-and-sandbox` |
| `lr` | List the coding-agent sessions started in this directory (Claude + Codex), newest first, with title and age; `Enter` resumes one |
| `lg` | Open LazyGit (inside a throwaway nvim; `Q` quits back to the shell) |
| `ld` | `lazydocker` |
| `lq [-r]` | Open lazysql on this repo's database: finds the repo's running postgres/mysql/mssql container and builds the URL from its port binding and env creds, else a sqlite file in the repo, else the bare picker (`-r` read-only) |
| `box` | `maestral` (Dropbox client; sign in with `box auth link`) |
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
| `gwta [branch\|pr#]` | Add a worktree tracking a remote branch or a PR number like `gh pr checkout` (fzf-picks a branch if omitted), then `cd` in |
| `gwtn [branch]` | Add a worktree on a new branch off the default branch, then `cd` in |
| `gwtr [-y] [branch]` | Remove a worktree (fzf-picks one if omitted), tear down its Docker containers/volumes/networks, and delete its branch, after confirmation (`-y` skips it) |

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
| `prefix x` | Kill pane, after a `y/n` confirm (auto-rebalance) |
| `prefix X` | Kill all other panes in the window, after a `y/n` confirm |
| `prefix y` | Toggle synchronize-panes |
| `prefix b` | Break pane out into its own window here (auto-rebalance) |
| `prefix B` | Break pane out into a brand-new session |
| `prefix G` | Gather current window back into the default (`tmp`) session |
| `prefix n` | Next session (repeatable, so hold the prefix and keep tapping). No `prefix p` twin, that key is the PR popup: go backwards with `Cmd+Shift+p` or tmux's own `prefix (` |
| `prefix p` | GitHub PR list popup (`tmux-gh-pr`, on a single key via `@gh-pr-key 'p'` instead of its default `pr` sequence). `j`/`k` move, `Enter` opens the detail view (`o` there opens that PR on github.com, `q` goes back), `/` filters, `o` opens the list on github.com, `r` refreshes, `q` quits |
| `prefix t` | Toggle light/dark theme (tmux + nvim + lazygit + the terminal) |
| `prefix T` | Date/time/uptime/calendar popup |
| `prefix u` | Show/hide the coding-agent usage block on the right status line (hidden also stops the usage fetch) |
| `prefix C` | Set/edit pane label |
| `prefix o` | Open this pane's GitHub PR in the browser (branch's PR, else the PR number leading the pane label / window name) |
| `prefix F` | fzf file picker (starts in `~/box`, or `ATTACH_ROOT`); pastes the chosen path into the pane to attach it to Claude Code / Codex. `Enter` descends into a directory or attaches a file, `^h` goes up, `Tab` marks several, `Esc` cancels |
| `prefix P` | Same for the macOS Photos library: fzf over recent photos with viu previews. `Enter` attaches, `^o` fetches the iCloud original first, `Tab` marks several, `☁` marks a photo that is not on this mac |
| `prefix V` | Attach the clipboard image to the pane: pulls it over the tailnet when the pane is on a machine you ssh'd into |
| `prefix m` | Render the copy-mode selection as a Mermaid diagram in the browser (select in copy mode first; clipboard untouched) |
| `prefix C-s` / `prefix C-r` | Save / restore tmux state (`tmux-resurrect`) |
| `prefix I` / `prefix U` / `prefix M-u` | Install / update / clean tmux plugins (`tpm`) |
| `prefix q` | Show pane index numbers (press a number to jump) |
| `prefix ↑↓←→` | Move between panes in any direction, including down (tmux default; covers the missing `C-j`) |
| `prefix ?` / `prefix /` | List every binding / press a key to see what it is bound to (tmux defaults, handy given how much is rebound here) |

**No prefix needed**

| Key | Action |
|---|---|
| `C-z` / `C-Up` | Toggle pane zoom |
| `C-x` / `C-y` | Half zoom: fill the column (full height) / fill the row (full width). Per-axis and per-pane, so a left and a right pane can both be maxed |
| `C-h/k/l` | Navigate between panes. No `C-j`: tmux resolves the prefix before any key table, so a `C-j` binding is unreachable while `C-j` is the prefix. `prefix Down` for the rest |
| `C-Down` | Choose a window from a tree (same as `prefix w`) |
| `S-Left` / `S-Right` | Previous / next window |
| `C-p` / `C-n` | Previous / next window |
| `C-S-Left` / `C-S-Right` | Reorder window left / right |
| `Cmd+1` .. `Cmd+8` | Jump to window index 0-7 (Alacritty translates the chord, see below) |
| `Cmd+9` | Jump to the last window (`Cmd+0` is left to Alacritty's font-size reset) |
| `Cmd+Shift+n` / `Cmd+Shift+p` | Next / previous session |
| `C-Right` | Arm the prefix, for one-tap leader on a phone keyboard |
| `C--` (or `C-_`, or `C-/`) | Toggle copy-mode. One binding, `C-_`: Ctrl with the `-`/`_` key sends byte `0x1F`, and so does `Ctrl+/` in most terminals, which is the name tmux gives that byte |
| `F12` | Nested tmux: put the local (outer) server to sleep so every key reaches the inner session; `F12` again wakes it (a chip on status-left marks the sleeping state) |

Plugins (via TPM): `tmux-resurrect`, `genkio/tmux-open-usage`, `genkio/tmux-spoony`, `genkio/tmux-gh-pr`. Resurrect captures pane contents; save/restore is manual via `prefix C-s` / `prefix C-r`. open-usage's own status injection is off (`@tmux_open_usage_enabled off`) because `tmux/bin/apply-theme.sh` inlines its script into `status-right` instead, to pick up the theme colour; `prefix u` hides that block.

**Copy mode (vi keys)**

| Key | Action |
|---|---|
| `y` | Copy selection verbatim (stays in copy mode, OSC52) |
| `Y` | Copy selection joined into one line (drops TUI padding + soft-wrap breaks) |
| `Enter` | Copy selection (stays in copy mode, OSC52) |
| Mouse drag | Copy on drag end (OSC52) |
| `C-h/k/l` | Navigate between panes without leaving scrollback |
| `NPage` / `C-d` | Page / half-page down. Not `C-f`: it is prefix2, and the prefix wins over every key table, so copy mode never sees it. `C-b` (page up) is fine |

**Copy mode: grab what is on the line** (`tmux-spoony`; these six are advertised
in the corner of the copy-mode indicator)

| Key | Action |
|---|---|
| `u` / `p` | Select the URL / path on this line |
| `c` / `i` | Select the command / IP address on this line |
| `x` | Select the whole line, indentation trimmed |
| `o` | Open the selection (URL, file, ...) and leave copy mode |

The Mermaid renderer is `prefix m`, not a bare `m` (the prefix table stays
reachable from copy mode, and default `m`, mark-pane, is unbound). When the tmux
server itself is remote, `prefix o` and `prefix m` copy the URL to your local
clipboard (OSC52) instead of opening a browser on the far end.

`prefix V` covers the other direction, where the clipboard is local and the agent
is remote: an ssh pty carries only text, so it reads `$SSH_CLIENT`, ssh's back to
that mac over the tailnet to dump the clipboard image, caches it in
`~/.cache/tmux-clip` (pruned after 7 days) and pastes that path. Peer account
names come from `@clip_ssh_users` in `.tmux.conf`, since `$SSH_CLIENT` is only an
IP; both machines need Tailscale SSH (`scripts/tailscale-up.sh`).

`prefix P` is `prefix F` against the Photos library, which no file picker can
walk: the listing is a read-only query of the library's sqlite db (so the
terminal needs Full Disk Access) and previews are viu block art, Alacritty
having no graphics protocol. What you pick is copied into `~/.cache/tmux-photo`
(pruned after 7 days), HEIC converted by sips, because the bundle path holds a
space the bare-path paste cannot carry. With iCloud "Optimize Mac Storage" most
originals are not on the mac at all: those rows are marked `☁`, the preview
names the resolution `Enter` would really attach (about a third of recent rows
have only a ~480px thumbnail), and `^o` asks Photos.app to fetch the true
original, which raises a one-time permission prompt. `ATTACH_PHOTO_LIMIT`
changes how many recent photos are listed (500).

---

## Alacritty

Primary terminal: transparent titlebar, OSC52 clipboard, `option`-as-`alt`.

| Key | Action |
|---|---|
| `Shift+Enter` | Insert newline (multi-line prompt) |
| `Cmd+Shift+Space` | Toggle vi mode (not the default `C-S-Space`, which a CJK input method eats) |
| `Cmd+Shift+Y` | Join the clipboard into one line (after a vi-mode `y`, strips TUI padding + soft-wrap breaks) |
| `Cmd+Shift+u/d/j/k` | Scroll the Claude Code transcript (sent as the alt+shift encoding, which tmux forwards untouched) |

Cmd never reaches the pty, so the window and session chords (`Cmd+1`..`Cmd+9`,
`Cmd+Shift+n/p`) are emitted here as private escapes and caught in `.tmux.conf`
as user-keys. The two files have to be kept in sync.

Theme: `Flexoki Light` / `TokyoNight Storm`. Toggle light/dark with `prefix + t` (or `scripts/theme-toggle.sh` outside tmux): it rewrites `~/.cache/dotfiles/alacritty-theme-active.toml` (Alacritty reloads it live) and repaints the running terminal via OSC. No splits/tabs - use tmux.

---

## Hammerspoon

`init.lua` loads seven modules from `hammerspoon/.hammerspoon`. Three own a
trigger key, one remaps two keys, two run with no keys at all.

### Rcmd launcher (hold right-Command)

Hold **right** Command (the left one is untouched) and tap a key. Hold it for
half a second without tapping to get an overlay of every binding. A key mapped
to more than one app opens a picker, chosen with `1`-`9` / `0`.

| Key | Target |
|---|---|
| `a` / `z` | Alacritty / Firefox (both fullscreen) |
| `c` / `m` / `f` | Calendar / Mail / Finder |
| `i` | iPhone Mirroring |
| `t` / `s` | TablePlus / Sublime Text |
| `u` / `w` | UURemote / WeChat |
| `o` | Open the front Finder window's folder in Alacritty |
| `q` | `vi ~/box/notes.txt` in Alacritty |
| `n` | Notification Center |
| `0` / `1` / `2` / `3` | Window: maximize / left half / right half / two-thirds |
| `` ` `` | Move the window to the next screen |
| `/` | Toggle "use F1, F2, etc. as standard function keys" (alerts which mode it landed in) |

The map lives in `rcmd.config.lua`; a value can be an app name, a bundle ID, a
list of apps, or one of the named actions.

### Homerow navigation

| Key | Action |
|---|---|
| `C-,` | Hint mode: yellow labels on the actionable elements of the focused window, type a label to click it |
| `C-/` | Same, but right-click the element (labels tinted blue) |
| `C-.` | Scroll mode: `j/k/h/l` scroll (`Shift` faster), `d`/`u` half page, `Space`/`S-Space` full page, `g`/`G` top/bottom, `Esc` exits. A window with several scrollable panes asks which one first (`1`/`2`/...) |

### Other triggers

| Key | Action |
|---|---|
| `Option+Space` | Raycast-lite palette: run an Apple Shortcut, or a quick link from `raycast.config.lua` (`{query}` placeholders) |
| `Cmd+Shift+S` | Selection OCR: drag a rectangle, and its text (Japanese + English, via Apple's Vision framework) lands on the clipboard |
| `F1` / `F2` | Escape / backtick, for an Apple Wireless Keyboard whose own keys are broken. Needs the standard-function-keys setting on, which `rcmd + /` toggles |

No keys of their own: `input_source` switches the macOS input source per app
(`input_source.config.lua`), and `uuremote_lock` starts the screen saver when a
UURemote session disconnects, so the lock screen keeps Fliqlo.

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
| `<leader>go` | Open the GitHub PR for the current branch (needs `gh`) |
| `<leader>gO` | Open the GitHub PR for the blamed line's commit (needs `gh`) |
| `<leader>lg` | Open LazyGit (default layout, command log hidden) |
| `<leader>lf` | Open LazyGit (folded layout: narrows the side panels for small screens) |
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
| `<leader>yR` | Copy the file's directory path to clipboard, `$HOME`-relative |
| `<leader>r` (visual) | Reflow: unwrap a hard-wrapped selection into one paragraph line |
| `<C-g>` | Show current file info (path, line count, position) on the command line |
| `Q` | Quit all windows (prompts to save/discard on unsaved changes) |
| `<Esc>` | Clear search highlight, the automatic cursor-word highlight, and the search counter |
| `zc` / `zo` (JSON/JSONC) | Close / open the `{`...`}` or `[`...`]` block under the cursor |
| `<leader>` then wait | Which-key popup of leader mappings (groups: Explorer, Git, LazyGit, Search, Diagnostics, Yank) |
| `<leader>?` | Show buffer-local keymaps |

### Automatic behaviors

- **Directory resume**: `nvim .` reopens the last real file you had focused in that directory.
- **Auto-save**: markdown / plain-text buffers auto-save on `InsertLeave`, `TextChanged`, `FocusLost`, but only when launched with a single file argument (e.g. `vi ~/notes/draft.md`). Bare `vi` and `vi some/folder/` leave it off.
- **Auto-reload**: files changed on disk reload automatically (notifies on reload).
- **Restore cursor**: reopening a file restores the last cursor position.
- **Cursor-word highlight**: idling on a word highlights its visible occurrences; moving the cursor clears it.
- **Search count**: `/` and `?` show `current/total` in the window's top right corner (live while typing, updated by `n` / `N`), since `cmdheight = 0` hides Neovim's own count.
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
