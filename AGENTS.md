# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Personal dotfiles managed with [GNU Stow](https://www.gnu.org/software/stow/). Most tool directories are stow packages, but this repo should use explicit package commands instead of `stow */` because `claude` and `codex` need special handling.

## Stow Commands

```bash
# Apply a single package (e.g. zsh config)
cd ~/dotfiles && stow zsh

# Apply the core packages
cd ~/dotfiles && stow brew git nvim tmux yazi zsh ssh

# Apply optional app packages
cd ~/dotfiles && stow hammerspoon

# Apply optional dev packages
cd ~/dotfiles && stow ghostty
cd ~/dotfiles && bash scripts/restore-claude-settings.sh
cd ~/dotfiles && bash scripts/restore-codex-config.sh

# Remove symlinks for a package
cd ~/dotfiles && stow -D zsh
```

## Brewfile Structure

- `brew/Brewfile` — meta file that sources both base and apps
- `brew/Brewfile.base` — CLI tools (always installed)
- `brew/Brewfile.apps` — GUI apps (opt-in with `--include-apps`)
- `brew/Brewfile.dev` — dev tools (ghostty, docker, gh, bun, sdkman-cli, claude-code, codex, etc.) for the explicit `--include-dev` flow; remaining version managers (volta, pyenv, rust) are installed via official curl installers in `setup-dev.sh`
- Install: `brew bundle --file brew/Brewfile.base` or `brew bundle --file brew/Brewfile`

## Automated Setup

`scripts/opinionated-flow.sh` clones the repo, installs base Brewfile, and stows core packages (`brew git nvim tmux yazi zsh`). It clones TPM into `~/.tmux/plugins/tpm` when missing and installs tmux plugins from `~/.tmux.conf` non-interactively. If `~/.gitconfig` already exists as a regular file, it warns and skips `git` instead of aborting. Pass `--include-apps` to install GUI apps and stow `hammerspoon`. Pass `--include-dev` to install dev tools (ghostty, docker, claude-code, codex, version managers, etc.), stow `ghostty` and `claude`, and seed `~/.codex/config.toml` from the tracked example when missing. Pass `--include-all` to enable both flows together.

## Stow Packages

| Package | Target | Notes |
|---------|--------|-------|
| `brew` | `~/brew/` | Brewfiles |
| `git` | `~/.gitconfig` | Shared Git config; private identity in machine-local `~/.gitconfig.local` |
| `zsh` | `~/.zshrc` | Oh My Zsh + vi mode + aliases |
| `nvim` | `~/.config/nvim/` | Kickstart.nvim-based config |
| `tmux` | `~/.tmux.conf` + `~/bin/` | Prefix: `C-j` / `C-f`; uses TPM + tmux-resurrect + tmux-continuum |
| `yazi` | `~/.config/yazi/` + `~/.config/yazi-mobile/` | Shared config for shell `yazi` and `yazi.nvim`; mobile profile for narrow Neovim UIs |
| `hammerspoon` | `~/.hammerspoon/` | Hammerspoon config and `rcmd` launcher module |
| `ghostty` | `~/.config/ghostty/` | Terminal emulator config |
| `claude` | `~/.claude/` | Use `scripts/restore-claude-settings.sh`; only `settings.json` and `statusline-command.sh` are linked |
| `vim` | `~/.vimrc` | Legacy vim config |
| `iterm2` | — | Empty/placeholder |

## Neovim Config

Based on kickstart.nvim. Single-file core at `nvim/.config/nvim/init.lua` (~48k). Custom extensions live in `nvim/.config/nvim/lua/custom/`:
- `keymaps.lua` — custom key mappings
- `copy_range.lua` — range copy utility
- `plugins/` — additional lazy.nvim plugin specs (aerial, auto-session, gitsigns extensions, snacks-gh, etc.)

Plugin specs in `lua/kickstart/plugins/` are the upstream kickstart extras (gitsigns, debug, lint, neo-tree, etc.).

Yazi config is stowed separately under `yazi/.config/`. The Neovim integration in `lua/custom/plugins/yazi.lua` points at the shared `~/.config/yazi` and `~/.config/yazi-mobile` homes so plain shell `yazi` and `yazi.nvim` share behavior.

## Clipboard / OSC52

A recurring pattern across tools: clipboard integration uses OSC52 escape sequences so copy works over SSH and inside tmux.
- `tmux/bin/osc52-copy.sh` — tmux copy helper
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
- `~/.gitconfig.local` — included from `.gitconfig` for private Git identity; seeded from `git/.gitconfig.local.example`, not stowed
- `~/.codex/config.toml` — machine-local Codex config; seeded from `codex/.codex/config.toml.example`, not stowed, because Codex persists project trust and permission state there
