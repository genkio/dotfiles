# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Personal dotfiles managed with [GNU Stow](https://www.gnu.org/software/stow/). Each top-level directory is a stow package — running `stow <package>` from `~/dotfiles` symlinks its contents into `$HOME`.

## Stow Commands

```bash
# Apply a single package (e.g. zsh config)
cd ~/dotfiles && stow zsh

# Apply all packages
cd ~/dotfiles && stow */

# Remove symlinks for a package
cd ~/dotfiles && stow -D zsh

# On Linux, lazygit needs: stow --ignore='^Library/' lazygit
```

## Brewfile Structure

- `brew/Brewfile` — meta file that sources both base and apps
- `brew/Brewfile.base` — CLI tools (always installed)
- `brew/Brewfile.apps` — GUI apps (opt-in with `--include-apps`)
- Install: `brew bundle --file brew/Brewfile.base` or `brew bundle --file brew/Brewfile`

## Automated Setup

`scripts/opinionated-flow.sh` clones the repo, installs base Brewfile, and stows core packages (`brew lazygit nvim tmux zsh`). Pass `--include-apps` to also install GUI apps and stow `claude ghostty`.

## Stow Packages

| Package | Target | Notes |
|---------|--------|-------|
| `brew` | `~/brew/` | Brewfiles |
| `zsh` | `~/.zshrc` | Oh My Zsh + vi mode + aliases |
| `nvim` | `~/.config/nvim/` | Kickstart.nvim-based config |
| `tmux` | `~/.tmux.conf` + `~/bin/` | Prefix: `C-j` / `C-f` |
| `ghostty` | `~/.config/ghostty/` | Terminal emulator config |
| `lazygit` | `~/.config/lazygit/` + `~/bin/` | Custom OSC52 clipboard |
| `claude` | `~/.claude/` | Claude Code settings + statusline |
| `opencode` | `~/.config/opencode/` | OpenCode config |
| `vim` | `~/.vimrc` | Legacy vim config |
| `iterm2` | — | Empty/placeholder |

## Neovim Config

Based on kickstart.nvim. Single-file core at `nvim/.config/nvim/init.lua` (~48k). Custom extensions live in `nvim/.config/nvim/lua/custom/`:
- `keymaps.lua` — custom key mappings
- `copy_range.lua` — range copy utility
- `plugins/` — additional lazy.nvim plugin specs (aerial, auto-session, gitsigns extensions, lazygit, snacks-gh, etc.)

Plugin specs in `lua/kickstart/plugins/` are the upstream kickstart extras (gitsigns, debug, lint, neo-tree, etc.).

## Clipboard / OSC52

A recurring pattern across tools: clipboard integration uses OSC52 escape sequences so copy works over SSH and inside tmux.
- `tmux/bin/osc52-copy.sh` — tmux copy helper
- `lazygit/bin/osc52-clip.sh` — lazygit copy helper
- Ghostty config enables `clipboard-read = allow` / `clipboard-write = allow`

## Commit Message Convention

Format: `type(scope): description`

Types: `add` (new feature/file), `update` (modify existing), `fix` (bug fix)
Scope: the affected package name(s), e.g. `zsh`, `nvim`, `brew`, `tmux`, `brew&zsh`

Examples from history:
- `update(zsh): remove cat alias`
- `add(script): opinionated flow`
- `fix(zsh): shell locale`

## Machine-Specific Config

Local overrides not tracked by git go in:
- `~/.zshrc.local` — sourced at end of .zshrc
- `~/.local/bin/env` — sourced at end of .zshrc
