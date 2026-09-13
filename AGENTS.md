# AGENTS.md

This file provides guidance to coding agents working in this repository.
`CLAUDE.md` is a symlink to it, so Claude Code and any agent reading
`AGENTS.md` get the same instructions with nothing to keep in sync.

## Overview

Personal dotfiles managed with [GNU Stow](https://www.gnu.org/software/stow/). Most tool directories are stow packages, but this repo should use explicit package commands instead of `stow */` because `claude`, `codex`, and `pi` need special handling.

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
cd ~/dotfiles && bash scripts/restore-pi-settings.sh

# Remove symlinks for a package
cd ~/dotfiles && stow -D zsh
```

## Brewfile Structure

- `brew/Brewfile` - meta file that sources both base and apps
- `brew/Brewfile.base` - CLI tools (always installed)
- `brew/Brewfile.apps` - GUI apps (opt-in with `--include-apps`)
- `brew/Brewfile.dev` - dev tools (gh, mise, codex, etc.) for the explicit `--include-dev` flow; `mise` manages node/python/go/uv + global npm CLIs via `mise/.config/mise/config.toml`. Claude Code installs via its official shell installer in `setup-dev.sh`. Pi installs as the `pi-coding-agent` formula; the formula pins the npm tarball and sets `PI_SKIP_VERSION_CHECK=1`, so update it with `brew upgrade`, never `pi update` (a self-update writes a second copy into Homebrew's `node_modules` and breaks the formula)
- Install: `brew bundle --file brew/Brewfile.base` or `brew bundle --file brew/Brewfile`

## Automated Setup

`scripts/opinionated-flow.sh` clones the repo, installs base Brewfile, and stows core packages (`brew mpv nvim tmux vim yazi zsh`). It pre-creates `~/.config/mpv` before stowing so mpv's runtime `watch_later/` state lands outside the dotfiles repo. It clones TPM into `~/.tmux/plugins/tpm` when missing and installs tmux plugins from `~/.tmux.conf` non-interactively. If `~/.gitconfig` already exists as a regular file, it warns and skips `git` instead of aborting. Pass `--include-apps` to install GUI apps, stow `hammerspoon`, and run `scripts/setup-sublime.sh` (Package Control + auto-installed packages, see below). Pass `--include-dev` to install dev tools (alacritty, mise, codex, etc.), stow `alacritty`, `mise`, and `claude`, seed Alacritty's active theme via `scripts/apply-alacritty-theme.sh`, install Claude Code via its shell installer, seed `~/.codex/config.toml` from the tracked example when missing, and run `scripts/restore-pi-settings.sh` to link the Pi extension and shared skills into `~/.pi/agent/`, install the `pi-web-access` package, and seed `~/.pi/agent/web-search.json` with the browser curator disabled. Pass `--include-all` to enable both flows together. With `--bootstrap-macos` it runs `scripts/macos-bootstrap.sh` with `DOTFILES_DEFER_TOUCHID=1` and calls `scripts/touchid-sudo.sh` itself as the final step, after killing the sudo keepalive: once `pam_tid` is in the sudo policy, sudo wants a fingerprint and stops accepting the piped password, so nothing that sudos may run after it.

On Intel macs the script installs Homebrew itself instead of running the official installer, which now aborts with "Homebrew on macOS is only supported on Apple Silicon processors!". The manual path clones `Homebrew/brew` into `/usr/local/Homebrew`, chowns the standard `/usr/local` prefix dirs to the current user, and symlinks `/usr/local/bin/brew`; `brew` still runs there. What Intel has lost is bottles: homebrew-core no longer builds macOS x86_64 ones, so any formula that has moved since builds from source or fails. The run is therefore slow and partial by design - `brew_bundle_install` keeps going past failures and prints a summary at the end. Requires the Xcode CLT (checked up front, since every source build needs it). `Brewfile.apps` already guards arm-only casks with `on_silicon`.

What Intel cannot absorb is a toolchain build: `go` and `rust` have no x86_64 bottle either, so a single Go or Rust CLI builds rustc (and llvm under it) or the Go toolchain from source, hours for a 3 MB binary. Homebrew does fall back to an older macOS bottle of the same arch (`find_older_compatible_tag`), so anything with a stale `sonoma` Intel bottle - bat, eza, fd, ripgrep, viu, zoxide, git-delta - still installs fine. The expensive formulae with no Intel bottle are guarded `if on_silicon` in `Brewfile.base` / `Brewfile.dev` and come from `scripts/install-intel-prebuilt.sh` instead, which installs the upstream darwin-amd64 release of each into `~/.local/opt/<tool>` with the binaries symlinked into `~/.local/bin` (first on PATH, and a non-brew symlink in brew's prefix would trip `brew doctor`). Covered: neovim, yazi, fzf, fastfetch, sevenzip, lnav (base); gh, lazygit, lazysql, mise (dev). `lnav` is pinned to the newest release that still publishes an Intel macOS artifact. Fastfetch 2.51.0 and 7-Zip 25.01 are held by the manifest's optional `pinned` upgrade policy: their newer Intel/universal assets require macOS 15 and 26 respectively, while these builds run on Sonoma. Mole is omitted on Intel: its release splits the shell tree and helper binaries across multiple artifacts rather than providing one self-contained archive; use its upstream installer if it is needed. The manifest fields are `set|name|repo|tag template|version|asset template|sha256|binaries|upgrade policy`; `{v}` is the version and `{vnd}` the version without dots. Version + sha256 belong together, same tradeoff as `install-alacritty.sh` - never edit one by hand without the other. `install-intel-prebuilt.sh base|dev` installs a set at the pins; with no argument it only reinstalls pins that drifted and never introduces a tool the machine lacks. `DOTFILES_FORCE_PREBUILT=1` bypasses the arch guard to exercise the manifest on Apple Silicon.

`--upgrade` asks each repo's GitHub API for the newest non-prerelease that still contains the configured Intel asset, installs it when it differs, and rewrites that record's version and sha256 in the manifest. Records with the `pinned` policy do not auto-upgrade because their newer artifacts raised the minimum macOS version. There is no pin to verify a brand-new version against, so the hash of what downloads becomes the pin - trust-on-first-use over TLS, after which every other machine verifies against it. An unreachable API leaves the pin alone rather than looking like a downgrade. `update.sh` runs this mode on Intel, which makes it the one step that can dirty the repo, so a repin is reported in the "needs your attention" summary: commit `scripts/intel-prebuilt.tsv` or the bump helps only the machine that ran it.

The remaining Intel-specific cases are:

- `tailscale` has no macOS CLI tarball, so `Brewfile.base` installs `cask "tailscale-app"` on Intel: the signed universal pkg, which puts the same CLI at `/usr/local/bin/tailscale` and runs the daemon as a system extension. `tailscale-up.sh` and `tailscale-exit.sh` are unaffected; what does not apply is `brew services`, so `opinionated-flow.sh` starts the service only when the formula is actually installed, and `update.sh`'s `tailscale_followups` exits early on a missing Cellar keg.
- `tmux` and `mpv` stay with brew and build from source: no darwin-amd64 asset, but they are C/C++ and their heavy dependencies still have compatible Intel bottles, so it is minutes rather than a toolchain.

The tap formulae need no guard: `carbonyl` and `cc-imessage` both carry `on_intel` blocks pointing at x86_64 release artifacts, and `herdlet` is python.

## Sublime Text

Installed as `cask "sublime-text"` in `brew/Brewfile.apps`. `scripts/setup-sublime.sh` (run by `--include-apps`; standalone via `make sublime`) provisions it headlessly:

- Bootstraps Package Control by downloading `Package Control.sublime-package` into `~/Library/Application Support/Sublime Text/Installed Packages/` when missing (non-fatal on network failure).
- Seeds the User `Package Control.sublime-settings` from `sublime/Package Control.sublime-settings` when absent, else merges the curated `installed_packages` into the existing file (union, preserving Package Control's runtime keys and GUI-added packages). Package Control installs listed-but-missing packages on launch.
- The merge tolerates Sublime's JSON-with-comments + trailing commas via a string-aware pre-parse in `python3` (`/usr/bin/python3` from Xcode CLT is always present once Homebrew is).
- Sets Sublime as the macOS default opener for text + code from `sublime/file-associations.txt` (UTIs + bare extensions, `#` comments). Bare extensions are resolved to UTIs by an inline `swift` snippet (`UTType(filenameExtension:)`) and `dyn.*` results dropped: an extension no installed app declares has no handler slot to set, so listing it was always a no-op. Current handler is read with `duti -d` and matches skipped, so a re-run on a provisioned machine writes nothing. Changes go in by rewriting `LSHandlers` in the `com.apple.launchservices.secure` domain (`defaults export` → `python3` `plistlib` → `defaults import`, then `killall lsd`), not via `duti -s`: the LaunchServices API pops a modal Finder confirmation per type, so a fresh machine used to stack ~30 dialogs. Do not edit that plist in place - cfprefsd caches the domain and flushes its copy back over a direct write. Bundle id is read from the app's `Info.plist` (fallback `com.sublimetext.4`). `duti` is a formula in `brew/Brewfile.apps`; absent → step skipped, non-fatal. This step runs before the package-list section so its early `exit 0`s don't skip it.
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
| `codex` | `~/.codex/` | Use `scripts/restore-codex-config.sh`; links `hooks.json` (tmux agent-state calls + herdlet), seeds machine-local `config.toml` from the tracked example |
| `pi` | `~/.pi/agent/` | Use `scripts/restore-pi-settings.sh`; links `settings.json`, `keybindings.json`, and `extensions/{tmux-agent-state,quiet-tools,usage-footer,deny-guard}.ts` (tmux agent-state hooks as in Claude/Codex; quiet-tools renders every tool row and thinking row at zero height until `Ctrl+O`, keeping one `✗ <tool> failed` line for errors; usage-footer replaces the footer with one line - context usage, session cost with the DeepSeek account balance, cwd, model - and halves DeepSeek off-peak pricing; deny-guard blocks the commands and paths from the Claude `permissions.deny` list and lets everything else run), installs `pi-web-access` via `pi install`, and seeds `web-search.json`. `trust.json` is machine-local, not stowed |
| `vim` | `~/.vimrc` | Config for the OS-shipped `/usr/bin/vim`; `vi` is shadowed to nvim via `zsh/.zsh_aliases` |

### Extension tests

`node scripts/test-deny-guard.mjs` exercises the deny-guard rule table against the extension's real `tool_call` handler with a stub `ExtensionAPI`: no pi session and no model calls. It asserts the allowed side as well as the blocked one, so add a case there when you touch a rule.

## Neovim Config

Active config lives in `nvim/.config/nvim/`, with the main setup in `nvim/.config/nvim/init.lua` and the tracked pack lockfile in `nvim/.config/nvim/nvim-pack-lock.json`.

Yazi config is stowed separately under `yazi/.config/` for shell `yazi`, with `yazi-mobile/` kept as a secondary compact profile.

## Clipboard / OSC52

A recurring pattern across tools: clipboard integration uses OSC52 escape sequences so copy works over SSH and inside tmux.
- `tmux/bin/osc52-copy.sh` - tmux copy helper
- Alacritty config sets `[terminal] osc52 = "CopyPaste"` (read+write clipboard allow)

## Cheatsheets

`CHEATSHEET.md` and `CHEATSHEET-tmux-alacritty.html` document the tmux and
Alacritty setup. They are two renderings of the same knowledge, so any change to
tmux or Alacritty config (a keybinding, a status-line element, a theme hook)
must update **both** in the same commit, not one and a promise about the other.

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
- `~/.pi/agent/settings.json` - tracked and stowed (linked to `pi/.pi/agent/settings.json`); pi rewrites it at runtime (`/settings`, `pi install`, changelog cursor), so those writes land in the repo as changes to commit, same as `claude/.claude/settings.json`. `trust.json` stays machine-local. The tracked file must have **no trailing newline**: pi persists settings as `JSON.stringify(settings, null, 2)` with none, and a newline makes every runtime write show up as a `\ No newline at end of file` diff on fresh machines. `keybindings.json` is the opposite - pi's keybinding migration writes `${JSON.stringify(config, null, 2)}\n`, so it keeps its newline
- `~/.pi/agent/web-search.json` - machine-local pi-web-access config (search workflow, providers, keys); seeded from `pi/.pi/agent/web-search.json.example`, not stowed, because the extension rewrites it when the curator changes providers
