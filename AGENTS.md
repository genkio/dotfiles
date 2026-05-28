# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Personal dotfiles managed with [GNU Stow](https://www.gnu.org/software/stow/). Most tool directories are stow packages, but this repo should use explicit package commands instead of `stow */` because `claude` and `codex` need special handling.

## Stow Commands

```bash
# Apply a single package (e.g. zsh config)
cd ~/dotfiles && stow zsh

# Apply the core packages
cd ~/dotfiles && mkdir -p ~/.config/mpv && stow brew git mpv nvim tmux vim yazi zsh ssh

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
- `brew/Brewfile.dev` — dev tools (ghostty, gh, mise, codex, etc.) for the explicit `--include-dev` flow; `mise` manages node/python/java + global npm CLIs via `mise/.config/mise/config.toml`. Claude Code installs via its official shell installer in `setup-dev.sh`
- Install: `brew bundle --file brew/Brewfile.base` or `brew bundle --file brew/Brewfile`

## Automated Setup

`scripts/opinionated-flow.sh` clones the repo, installs base Brewfile, and stows core packages (`brew git mpv nvim tmux vim yazi zsh`). It pre-creates `~/.config/mpv` before stowing so mpv's runtime `watch_later/` state lands outside the dotfiles repo. It clones TPM into `~/.tmux/plugins/tpm` when missing and installs tmux plugins from `~/.tmux.conf` non-interactively. If `~/.gitconfig` already exists as a regular file, it warns and skips `git` instead of aborting. Pass `--include-apps` to install GUI apps and stow `hammerspoon`. Pass `--include-dev` to install dev tools (ghostty, mise, codex, etc.), stow `ghostty`, `mise`, and `claude`, install Claude Code via its shell installer, and seed `~/.codex/config.toml` from the tracked example when missing. Pass `--include-all` to enable both flows together.

## Stow Packages

| Package | Target | Notes |
|---------|--------|-------|
| `brew` | `~/brew/` | Brewfiles |
| `git` | `~/.gitconfig` | Shared Git config; private identity in machine-local `~/.gitconfig.local` |
| `zsh` | `~/.zshrc` | Oh My Zsh + vi mode + aliases |
| `nvim` | `~/.config/nvim/` | Daily-driver Neovim 0.12 profile launched with `nvim` |
| `tmux` | `~/.tmux.conf` + `~/bin/` | Prefix: `C-j` / `C-f`; uses TPM + tmux-resurrect + tmux-continuum |
| `yazi` | `~/.config/yazi/` + `~/.config/yazi-mobile/` | Shell `yazi` config with a secondary compact profile |
| `mpv` | `~/.config/mpv/` | Media player; pre-create `~/.config/mpv` before stowing to avoid folding (runtime `watch_later/` writes back to its config dir) |
| `hammerspoon` | `~/.hammerspoon/` | Hammerspoon config and `rcmd` launcher module |
| `ghostty` | `~/.config/ghostty/` | Terminal emulator config |
| `mise` | `~/.config/mise/` | Polyglot version manager (node/python/java + global npm CLIs) |
| `claude` | `~/.claude/` | Use `scripts/restore-claude-settings.sh`; only `settings.json` and `statusline-command.sh` are linked |
| `vim` | `~/.vimrc` | Config for the OS-shipped `/usr/bin/vim`; `vi` is shadowed to nvim via `zsh/.zsh_aliases` |
| `iterm2` | — | Empty/placeholder |

## Neovim Config

Active config lives in `nvim/.config/nvim/`, with the main setup in `nvim/.config/nvim/init.lua` and the tracked pack lockfile in `nvim/.config/nvim/nvim-pack-lock.json`.

Yazi config is stowed separately under `yazi/.config/` for shell `yazi`, with `yazi-mobile/` kept as a secondary compact profile.

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
