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
cd ~/dotfiles && stow alacritty && bash scripts/apply-alacritty-theme.sh
cd ~/dotfiles && bash scripts/restore-claude-settings.sh
cd ~/dotfiles && bash scripts/restore-codex-config.sh

# Remove symlinks for a package
cd ~/dotfiles && stow -D zsh
```

## Brewfile Structure

- `brew/Brewfile` - meta file that sources both base and apps
- `brew/Brewfile.base` - CLI tools (always installed)
- `brew/Brewfile.apps` - GUI apps (opt-in with `--include-apps`)
- `brew/Brewfile.dev` - dev tools (gh, mise, codex, etc.) for the explicit `--include-dev` flow; `mise` manages node/python/go/uv + global npm CLIs via `mise/.config/mise/config.toml`. Claude Code installs via its official shell installer in `setup-dev.sh`
- Install: `brew bundle --file brew/Brewfile.base` or `brew bundle --file brew/Brewfile`

## Automated Setup

`scripts/opinionated-flow.sh` clones the repo, installs base Brewfile, and stows core packages (`brew mpv nvim tmux vim yazi zsh`). It pre-creates `~/.config/mpv` before stowing so mpv's runtime `watch_later/` state lands outside the dotfiles repo. It clones TPM into `~/.tmux/plugins/tpm` when missing and installs tmux plugins from `~/.tmux.conf` non-interactively. If `~/.gitconfig` already exists as a regular file, it warns and skips `git` instead of aborting. Pass `--include-apps` to install GUI apps, stow `hammerspoon`, and run `scripts/setup-sublime.sh` (Package Control + auto-installed packages, see below). Pass `--include-dev` to install dev tools (alacritty, mise, codex, etc.), stow `alacritty`, `mise`, and `claude`, seed Alacritty's active theme via `scripts/apply-alacritty-theme.sh`, install Claude Code via its shell installer, and seed `~/.codex/config.toml` from the tracked example when missing. Pass `--include-all` to enable both flows together.

## Sublime Text

Installed as `cask "sublime-text"` in `brew/Brewfile.apps`. `scripts/setup-sublime.sh` (run by `--include-apps`; standalone via `make sublime`) provisions it headlessly:

- Bootstraps Package Control by downloading `Package Control.sublime-package` into `~/Library/Application Support/Sublime Text/Installed Packages/` when missing (non-fatal on network failure).
- Seeds the User `Package Control.sublime-settings` from `sublime/Package Control.sublime-settings` when absent, else merges the curated `installed_packages` into the existing file (union, preserving Package Control's runtime keys and GUI-added packages). Package Control installs listed-but-missing packages on launch.
- The merge tolerates Sublime's JSON-with-comments + trailing commas via a string-aware pre-parse in `python3` (`/usr/bin/python3` from Xcode CLT is always present once Homebrew is).
- Sets Sublime as the macOS default opener for text + code via `duti -s <bundle> <entry> all` over `sublime/file-associations.txt` (UTIs + bare extensions, `#` comments). Layered (broad parent UTIs + explicit extensions) since UTI cascade misses types with their own UTI. Bundle id is read from the app's `Info.plist` (fallback `com.sublimetext.4`). `duti` is a formula in `brew/Brewfile.apps`; absent → step skipped, non-fatal. Per-entry failures (unregistered type) are counted and skipped. This step runs before the package-list section so its early `exit 0`s don't skip it.
- First launch on a fresh machine bootstraps Package Control (dependency→library migration, prompts to restart); seeded packages install after one quit/reopen. Deliberately not automated: launching the GUI mid-`make` and quitting on a timer risks quitting mid-install (half-migrated syntax errors), worse than a clean manual restart. `setup-sublime.sh` prints this expectation instead.

`sublime/Package Control.sublime-settings` is the source of truth for the package list; it is **seeded, not stowed** (same reason as `~/.codex/config.toml`: Package Control rewrites the live file at runtime). `sublime/.stow-local-ignore` keeps `stow sublime` a no-op. To add a package: install it via `Package Control: Install Package`, add the name to the tracked file, and re-run `make sublime` elsewhere.

## Stow Packages

| Package | Target | Notes |
|---------|--------|-------|
| `brew` | `~/brew/` | Brewfiles |
| `git` | `~/.gitconfig` + `~/.gitignore_global` | Shared Git config and global ignore; private identity in machine-local `~/.gitconfig.local` |
| `zsh` | `~/.zshrc` | Oh My Zsh + vi mode + aliases |
| `nvim` | `~/.config/nvim/` | Daily-driver Neovim 0.12 profile launched with `nvim` |
| `tmux` | `~/.tmux.conf` + `~/bin/` | Prefix: `C-j` / `C-f`; uses TPM + tmux-resurrect |
| `yazi` | `~/.config/yazi/` + `~/.config/yazi-mobile/` | Shell `yazi` config with a secondary compact profile |
| `mpv` | `~/.config/mpv/` | Media player; pre-create `~/.config/mpv` before stowing to avoid folding (runtime `watch_later/` writes back to its config dir) |
| `hammerspoon` | `~/.hammerspoon/` | Hammerspoon config and `rcmd` launcher module |
| `alacritty` | `~/.config/alacritty/` | Terminal emulator (Flexoki Light / TokyoNight Storm). Run `scripts/apply-alacritty-theme.sh` after stow to seed the active theme; light/dark is driven by `theme-toggle.sh` (tmux `prefix + t`), which rewrites the active theme and repaints the running terminal via OSC |
| `mise` | `~/.config/mise/` | Polyglot version manager (node/python/go/uv + global npm CLIs) |
| `claude` | `~/.claude/` | Use `scripts/restore-claude-settings.sh`; the whole package is linked (`settings.json`, `statusline-command.sh`, `keybindings.json`, plus the `rules/` and `hooks/` dirs) |
| `vim` | `~/.vimrc` | Config for the OS-shipped `/usr/bin/vim`; `vi` is shadowed to nvim via `zsh/.zsh_aliases` |

## Neovim Config

Active config lives in `nvim/.config/nvim/`, with the main setup in `nvim/.config/nvim/init.lua` and the tracked pack lockfile in `nvim/.config/nvim/nvim-pack-lock.json`.

Yazi config is stowed separately under `yazi/.config/` for shell `yazi`, with `yazi-mobile/` kept as a secondary compact profile.

## Clipboard / OSC52

A recurring pattern across tools: clipboard integration uses OSC52 escape sequences so copy works over SSH and inside tmux.
- `tmux/bin/osc52-copy.sh` - tmux copy helper
- Alacritty config sets `[terminal] osc52 = "CopyPaste"` (read+write clipboard allow)

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
- `~/.zshrc.local` - sourced at end of .zshrc
- `~/.local/bin/env` - sourced at end of .zshrc
- `~/.gitconfig.local` - included from `.gitconfig` for private Git identity; seeded from `git/.gitconfig.local.example`, not stowed
- `~/.codex/config.toml` - machine-local Codex config; seeded from `codex/.codex/config.toml.example`, not stowed, because Codex persists project trust and permission state there
