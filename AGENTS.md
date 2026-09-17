# AGENTS.md

This file provides guidance to coding agents working in this repository.
`CLAUDE.md` is a symlink to it, so Claude Code and any agent reading
`AGENTS.md` get the same instructions with nothing to keep in sync.

## Overview

Personal dotfiles managed with [GNU Stow](https://www.gnu.org/software/stow/). Most tool directories are stow packages, but this repo should use explicit package commands instead of `stow */` because `claude` and `pi` need special handling.

## Stow Commands

```bash
# Apply a single package (e.g. zsh config)
cd ~/dotfiles && stow zsh

# Apply the core packages
cd ~/dotfiles && mkdir -p ~/.config/mpv && stow brew git mpv nvim tmux vim yazi zsh ssh

# Apply optional app packages
cd ~/dotfiles && stow hammerspoon aerospace

# Apply optional dev packages
cd ~/dotfiles && stow alacritty && bash scripts/apply-alacritty-theme.sh
cd ~/dotfiles && bash scripts/restore-claude-settings.sh
cd ~/dotfiles && bash scripts/restore-pi-settings.sh

# Remove symlinks for a package
cd ~/dotfiles && stow -D zsh
```

`scripts/restow.sh` (`make stow`, and the stow step of `make update`) relinks everything, **one package per `stow` invocation**. That is not cosmetic: stow aborts the whole invocation on a single conflict, so a batched call meant one bad package took the other thirteen down with it and reported `All operations aborted` under a list of links it had just claimed to make. On a target-side conflict it asks, on `/dev/tty`, whether to rename the offending file aside (`<name>.bak-<stamp>`) and stow over it; with no tty (cron, `ssh host make update`) it reports and moves on, and the script exits non-zero naming the packages it left unstowed.

**Never commit an absolute symlink inside a package.** stow refuses to stow one and aborts, and the path it names is per-arch anyway (`/opt/homebrew` vs `/usr/local`). Two got committed by `herdlet setup` writing through stow links into the checkout: `pi/.pi/agent/extensions/herdlet.ts` (which aborted every restow) and `skills/herdlet/SKILL.md` (which only escaped that because stow folds a skill directory into one link and never descends into it, so it silently pointed at a nonexistent path on Intel). Both are now machine-local, written by `scripts/link-herdlet.sh` into `~/.pi/agent/extensions`, `~/.claude/skills/herdlet` and `~/.pi/agent/skills/herdlet` - real directories, which is also what keeps a future `herdlet setup` out of the repo. It links into the keg rather than copying, so a herdlet upgrade carries the content; `make update` and both `restore-*-settings.sh` scripts call it, and it is a no-op when herdlet is not installed.

## Brewfile Structure

- `brew/Brewfile` - meta file that sources base and apps
- `brew/Brewfile.base` - the CLI tools Homebrew is still the right tool for: bottled on both arches, or a small C build. Five former entries (fastfetch, fzf, neovim, sevenzip, yazi) now come from `mise/.config/mise/conf.d/cli.toml` instead, installed by the same `core` phase
- `brew/Brewfile.apps` - GUI apps, plus the media player: `mpv` on Apple Silicon, `cask "iina"` on Intel (opt-in with `make apps`)
- `brew/Brewfile.dev` - dev tools (awscli, gnupg, lazydocker, etc.) for the explicit `make dev` flow; `mise` manages the language toolchains, `gh`, `pi`, `lazygit`, `lazysql` and the global npm CLIs (see the mise section below). Claude Code installs via its official shell installer in `setup-dev.sh`
- Install: `brew bundle --file brew/Brewfile.base` or `brew bundle --file brew/Brewfile`
- Three tools are pinned outside brew and installed by script: Alacritty (`scripts/install-alacritty.sh`, cask disabled upstream), Fliqlo (`scripts/install-fliqlo.sh`) and mise (`scripts/install-mise.sh`). Fliqlo left the cask list because `macos-bootstrap.sh` selects it as the screen saver and needs the bundle on disk at selection time, which is before `Brewfile.apps` would have run. Its host refuses hotlinked downloads, so the script sends a `Referer`; it and Alacritty verify a pinned sha256 before mounting, and `make update` re-runs both. mise has no local pin because mise.run verifies the release against its own published `SHASUMS256.txt`, so a pin would only freeze the version

### Intel Macs

Homebrew moved Intel macOS to Tier 3, stopped building x86_64 bottles, and plans to drop Intel entirely in September 2027 or later ([Support Tiers](https://docs.brew.sh/Support-Tiers)). Homebrew falls back to a bottle built for an *older* macOS of the same arch, so an Intel Mac on Sonoma or newer still gets whatever was bottled before the cutoff; below Sonoma, effectively everything compiles.

**The installer refuses Intel outright.** Since 2026-09-04 (Homebrew/install `e078684`, "Remove Intel macOS support from installer") `install.sh` aborts with *"Homebrew on macOS is only supported on Apple Silicon processors!"*, and there is no override flag. `brew` itself has no such check and still runs on Intel, so only the installer is in the way: `opinionated-flow.sh` pins the Intel path to `7a133dcc`, the commit before that change, which still knows the `/usr/local` prefix. arm64 tracks `HEAD`. The arch test is `sysctl hw.optional.arm64` and not `uname -m`, which reports `x86_64` for a terminal running under Rosetta on an Apple Silicon mac and would send it down the Intel path. That pin gets no `check-pins.sh` entry on purpose: the repo's other pins exist because upstream had a problem that might get fixed, and this is the opposite, so the audit would never fire.

On Intel the prefix is `/usr/local`, not `/opt/homebrew`. Everything that needs to know already tries both (`zsh/.zshrc`, `scripts/touchid-sudo.sh`, `tmux/bin/clip-png.sh`, `tmux/bin/client-theme.sh`, `hammerspoon/.hammerspoon/uuremote_monitor.lua`); prefer `brew --prefix` over a literal in anything new.

Packages left Homebrew because of this. Each ships an official prebuilt x86_64 binary that the formula would have rebuilt, and most dragged in a toolchain far larger than themselves:

| Package | Formula would build | Now from |
|---|---|---|
| `mise` | LLVM 23 + LLVM 22 + rustc (build deps `llvm`, `rust`) | `scripts/install-mise.sh` (mise.run) |
| `yazi` | rustc, and `rust` depends on `llvm@22` | `aqua:` in `conf.d/cli.toml`, installed by `core` |
| `fzf` | the Go toolchain | `aqua:junegunn/fzf` |
| `neovim`, `fastfetch`, `sevenzip` | cmake/pkgconf/imagemagick chains | `aqua:` in `conf.d/cli.toml` |
| `pi-coding-agent` | node from source, plus rustc as a build dep | `npm:@earendil-works/pi-coding-agent` in mise |
| `gh` | the Go toolchain | `aqua:cli/cli` in mise (the cli/cli release asset) |
| `lazygit`, `lazysql` | the Go toolchain: neither has an x86_64 macOS bottle, and the build dep `go` has none either | `aqua:` in `conf.d/dev.toml` |
| `ffmpeg` | sdl3, sdl2-compat, libvmaf | still brew, moved to `Brewfile.dev` |
| `mpv` | shaderc, luajit, libass, libplacebo, mujs, yt-dlp | `Brewfile.apps`: `cask "iina"` on Intel, mpv elsewhere |
| `tailscale` | the Go toolchain | still brew, but `make tailscale` installs it, not a phase |

The aqua entries resolve to the same versions Homebrew ships, checked at the time of the move (yazi 26.9.1, fzf 0.74.4, neovim 0.12.5, fastfetch 2.68.1, 7zip 26.03, lazygit 0.65.1, lazysql 0.5.7), so this is a delivery change and not a downgrade.

`lnav` is gone rather than moved. lnav 0.14 ships only an `aarch64-macos` asset and the aqua registry marks it unsupported on `darwin/amd64`, so `mise install` failed on Intel on every run; pinning 0.13.2 would have frozen every machine for one platform's sake, and the brew formula compiles Rust. Nothing in the repo depended on it.

**The rule for what belongs where**, since the line will drift as Homebrew rebuilds more formulae and more of them lose their stale Sonoma bottles: a CLI tool stays in `Brewfile.base` while Homebrew is still the right tool for it, meaning it is bottled on both arches or is a small C build with bottled deps. When it loses its x86_64 bottle *and* has an aqua entry that supports `darwin/amd64` (check the registry's `supported_envs` and that the latest release actually ships an x86_64 macOS asset), move it to the `conf.d/` file whose phase already installs it - `cli.toml` for a `core` tool, `dev.toml` for a `dev` one - so the move never changes which machines get it. When it loses the bottle and has no prebuilt binary anywhere, it goes to whichever opt-in target actually wants it, never `Brewfile.base`. `tmux` is the current example of the first case (no upstream macOS binary exists, but its deps are bottled, so it is the one thing `core` still compiles on Intel and it takes minutes); `mole` used to be the example of the last case and was dropped instead: no aqua entry, its release tarball ships `analyze`/`status` binaries but no `mole`, and nothing in this repo ever invoked it.

**When there is no prebuilt binary and no substitute, the last resort is an `on_intel` guard in the Brewfile.** Three exist, measured on a 2020 Intel MacBook Pro where `make all` took 3732s: `gnupg` (~900s with gmp and libgcrypt, and only `make gpg-key` wants it - use SSH signing there instead), `awscli` (~300s with its twelve `aws-c-*` libraries, and nothing in the repo calls it), and `mpv`, replaced by `cask "iina"` - the same engine as a universal `.app`, saving ~700s. Two traps: IINA's CLI is named `iina`, so `yazi/.config/yazi/yazi.toml` picks the binary at run time rather than naming one (that file is stowed on both arches); and a guard never uninstalls, since nothing here runs `brew bundle cleanup`. Upgrading macOS is not an alternative - Sonoma is the newest Intel bottle Homebrew builds and the fallback only looks downward, so no macOS version reaches more x86_64 bottles than Sequoia already does.

`PI_SKIP_VERSION_CHECK=1` moved from the Homebrew formula's wrapper to `zsh/.zshrc`: mise owns pi's version, and a `pi update` would install a second copy beside it. Existing machines keep their Homebrew copies until you `brew uninstall` them by hand; `~/.local/bin` and mise's shims come first on PATH, so the new ones win meanwhile.

## Automated Setup

`scripts/opinionated-flow.sh` runs as **phases**: `--phase macos|core|apps|dev|touchid`, repeatable and required, and the Makefile target per phase is `make macos` / `core` / `apps` / `dev` / `touchid`. `make all` passes all five to a single process so the password is asked for once. The order is fixed inside the script, not by flag order, because `touchid` must follow the last sudo of the whole run.

A bare `make` is `.DEFAULT_GOAL := menu`, which runs `scripts/pick-phases.sh`: a checkbox list of the six phases that execs `opinionated-flow.sh` with whatever is ticked. All six start ticked, so Enter reproduces the old bare-`make` behaviour. Three constraints shaped it and should survive any edit:

- **No dependencies.** `fzf` would be the obvious picker and is wrong here, because it arrives with the `core` phase the menu exists to offer. Builtins and `stty` only.
- **It draws on `/dev/tty`, not stdout**, so `make 2>&1 | tee setup.log` still works and the redraw frames stay out of the log. With no controlling terminal it prints the target names and exits 1 instead of blocking on a read that can never return.
- **macOS ships bash 3.2**, and `/usr/bin/env bash` on a fresh machine is exactly that. Fractional `read -t` is a hard error there, so the escape-sequence timeout is `-t 1`; do not "fix" it to a fraction.

Run `make macos` first on a new machine: it disables the macOS automatic update that would otherwise saturate the uplink for the rest of the run, enables Remote Login, and prints the machine's local IP so the slow phases can be driven over ssh. `apps` also wants it to have run, though nothing enforces the order: that phase stows `aerospace`, whose `gaps.outer.top` is sized on the assumption the menu bar is auto-hidden, which is a `macos` write. Out of order the top gap is simply wrong until `macos` runs.

Capturing the sudo password is the only **preamble**. The script never clones: it resolves its own repo root from `BASH_SOURCE` and operates there, since getting the script onto the machine already required the checkout. Homebrew and stow are installed by the `core` phase, so `make macos` pulls nothing from brew; `apps` and `dev` refuse to run without it and tell you to run `make core` first. The `macos` phase needs the Xcode CLT for `/usr/bin/python3` (Dock rewrite, wallpaper store) and asserts it with `xcode-select -p` rather than installing it: `/usr/bin/git` is a CLT shim too, so cloning this repo already triggered the install. The assert exists only to turn the miss into an error, because `/usr/bin/python3` without CLT pops a GUI dialog and blocks forever over ssh.

Presence is not enough for the `core` phase, though, so it opens with `ensure_clt_current` (in `scripts/lib.sh`). Homebrew refuses to install **any** formula, bottled ones included, when the CLT predate the running macOS - `Error: Your Command Line Tools are too outdated` - and a macOS *major upgrade leaves the old CLT in place*, with `xcode-select -p` still answering happily. That is what turned a whole `make` run into 12 failed formulae after a VM went 26 → 27 carrying CLT 16.4. The required major comes from a two-line table rather than a lookup, because Apple aligned Xcode with macOS at 26 (Xcode 26 → macOS 26) and ran one ahead before it (Xcode 16 → macOS 15): `os >= 26 ? os : os + 1`, the same table Homebrew's `CLT.minimum_version` uses. The update is driven through `softwareupdate -i`, not `xcode-select --install`, whose modal dialog nothing can answer over ssh; the sentinel file in `/tmp` is what makes `softwareupdate -l` list the CLT package at all. Fatal when it cannot get there, since the alternative is twenty minutes of failing one package at a time.

The `core` phase installs base Brewfile and stows core packages (`brew mise mpv nvim tmux vim yazi zsh`). It then installs mise via `scripts/install-mise.sh` and the CLI group from `mise/.config/mise/conf.d/cli.toml` - stow first, because mise only puts a tool on PATH if it is in the config, so installing before the config lands would leave six binaries nothing can find. The group is read out of that file with a sed over its quoted keys rather than listed a second time in the script, and a bare `mise install` is deliberately not used: it would pull the dev toolchains from `config.toml` too, which is the split the phases exist to keep. It pre-creates `~/.config/mpv` before stowing so mpv's runtime `watch_later/` state lands outside the dotfiles repo. It clones TPM into `~/.tmux/plugins/tpm` when missing and installs tmux plugins from `~/.tmux.conf` non-interactively. If `~/.gitconfig` already exists as a regular file, it warns and skips `git` instead of aborting. The `apps` phase installs GUI apps, stow `hammerspoon`, `aerospace` and `sketchybar`, and run `scripts/setup-sublime.sh` (Package Control + auto-installed packages, see below); it also installs the media player, `mpv` on Apple Silicon and `cask "iina"` on Intel. The `dev` phase installs dev tools, stow `alacritty` and `claude`, seed Alacritty's active theme via `scripts/apply-alacritty-theme.sh`, install the remaining mise tools with a bare `mise install`, which covers both `config.toml` and `conf.d/dev.toml` (mise itself already arrived with `core`; `setup-dev.sh` only installs it when missing, for a standalone `make dev`), install Claude Code via its shell installer, and run `scripts/restore-pi-settings.sh` to link the Pi extension and shared skills into `~/.pi/agent/`, install the `pi-web-access` package, and seed `~/.pi/agent/web-search.json` with the browser curator disabled. It activates mise with `--shims` rather than the plain hook: the plain one resolves tool bin dirs once and refreshes on a prompt hook that never fires in a script, so `pi` and `gh` (installed on the following line) would stay off PATH for the rest of the file. The `macos` phase runs `scripts/macos-bootstrap.sh` with `DOTFILES_DEFER_TOUCHID=1`; the `touchid` phase calls `scripts/touchid-sudo.sh` as the final step, after killing the sudo keepalive: once `pam_tid` is in the sudo policy, sudo wants a fingerprint and stops accepting the piped password, so nothing that sudos may run after it.

### Wallpaper and screen saver

Both live in WallpaperAgent's store (`~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`), and `macos-bootstrap.sh` writes **both** by walking that tree and killing the agent either side, rather than through any API.

The screen saver has worked that way for a while: module selection left the ByHost `com.apple.screensaver` domain in macOS 14, and the store repeats the choice at every node - all-displays, system default, and one per display and per space - keyed by *this* machine's UUIDs, so it has to be walked, not seeded from a captured file.

The wallpaper is **split on the OS major**, and that split is load-bearing - `set_wallpaper` dispatches to `set_wallpaper_api` below 27 and `set_wallpaper_store` at 27 and above. Do not collapse it into one path; both single-path versions were tried and each breaks a release.

Up to 26 it is `NSWorkspace.setDesktopImageURL`, which covers every node. On 27 that same call reaches `SystemDefault`, `Displays/<uuid>` and a `Spaces` entry keyed by the **empty string**, but leaves the node for the space actually on screen (`Spaces/<space-uuid>/...`) on the old image - and still returns true, so the run reports success and nothing changes. It is also unusable as a first step feeding a repair pass, because whether the agent has persisted the call to `Index.plist` by the time you read it is pure timing (measured between 100ms and never), so a poll either races or copies the *previous* image over every node. Hence the direct walk on 27 only. The store walk is **not** a drop-in for older releases: it was tried on 15.x and set no wallpaper there, so the gate is the fix, not a stylistic choice.

The two walks stay separate and must not clobber each other: the desktop walk skips every `Idle` node, and the screen-saver walk only rewrites `Idle` (unlinking a fresh account's `Linked` node first, keeping its wallpaper as `Desktop`).

### Routine updates (`make update`)

`scripts/update.sh` upgrades an already-provisioned machine: brew, mise's `conf.d/` set, the three tools pinned outside brew, a restow, the machine-local seeds, and `check-pins.sh`. Every step is non-fatal and anything actionable is reprinted as one block at the end, because six chatty steps bury the two lines that need a decision. `--dry-run` reports through each tool's own simulation.

It **does** install: `brew bundle` runs for `brew/Brewfile` (base + apps) and `brew/Brewfile.dev`, gated behind `brew bundle check` so a satisfied Brewfile costs a second rather than the minutes a no-op bundle spends re-resolving casks. `trust_brewfile_taps` (in `lib.sh`) runs first, because Homebrew will not load a non-official tap's formulae until they are trusted and `trust.json` is **machine-local** - a machine provisioned before its Brewfile gained a tap, or before brew had `trust` at all, arrives here untrusted. Untrusted does not merely fail to install: `brew bundle check` reports an installed tap formula as "needs to be installed or updated", so every pass would try that tap again and die on it. The tap list is **read out of the Brewfiles**, never written down, which is the fix for how this broke - the trust step existed only in `opinionated-flow.sh` with three taps named by hand, and the new `brew bundle` had no equivalent. `setup-dev.sh` calls it too, for the day `Brewfile.dev` gains a tap. It used to be upgrade-only on the grounds that this is not a provisioner, and the cost was silence: an entry added to a Brewfile on one machine reached the others only through a full `make apps` / `make dev`, which is not what anyone runs on a Tuesday, so it never arrived. The trade that comes with it: the first run converges a core-only machine to the GUI apps and the dev tools too.

mise is the exception and stays split: `update.sh` intersects `conf.d/` with what is installed, because `mise upgrade <tool>` on a missing tool installs it, and nothing here can tell a dev tool that was never wanted from one that is merely not installed yet.

## mise config layout

Three files, and the split carries two orthogonal meanings at once: **which phase installs it**, and **whether `make update` upgrades it**.

| File | Holds | Installed by | `make update` |
|---|---|---|---|
| `conf.d/cli.toml` | neovim, yazi, fzf, fastfetch, sevenzip (all `aqua:`) | `core`, by name | upgrades |
| `conf.d/dev.toml` | `gh`, `pi`, `lazygit`, `lazysql`, `ctx7`, `@playwright/cli` | `dev`, via bare `mise install` | upgrades |
| `config.toml` | node, python, go, uv, typescript, typescript-language-server | `dev`, via bare `mise install` | **frozen** |

The rule is: **everything in `conf.d/` is tracked to latest; `config.toml` is the frozen set.** A working toolchain buys nothing from a global bump and project-local pins resolve independently, which is the long-standing policy. Everything in `conf.d/` is there because `brew upgrade` used to keep it current when it was a formula, and losing that when it moved to mise was a regression rather than a decision.

Consequences worth knowing before editing any of them:

- `update.sh` and `opinionated-flow.sh` both read conf.d files with `sed -n 's/^[[:space:]]*"\([^"]*\)"[[:space:]]*=.*/\1/p'`, so **keys in conf.d must stay quoted `backend:name` strings**. Bare keys like `node = "lts"` are invisible to it, which is exactly why the toolchains live in `config.toml`.
- `update.sh` never passes `--bump`, and `mise upgrade` honours whatever range each entry asks for. That is what makes it safe to keep the deliberate `"npm:@playwright/cli" = "0.1.20"` supply-chain pin inside an auto-upgraded file: it stays put until the line changes, then starts tracking latest on its own.
- `scripts/check-pins.sh` reads that pin out of `conf.d/dev.toml`. If the pin moves file again, update the path there too - a miss is silent, since the audit would just report "not pinned, nothing to audit".

### Why mise's Homebrew backend is not used

`[bootstrap.packages]` with `brew:` entries is the obvious candidate for replacing `brew bundle`: `mise bootstrap packages` pours Homebrew's bottles from ghcr.io into the same prefix, writes brew-compatible receipts, and never shells out to `brew`. It is not used, and the blocker is the Intel split itself: **the backend declares itself unavailable on Intel macOS** (mise.jdx.dev/bootstrap/packages/brew.html, "Supported platforms"), so every `brew:` entry is skipped there - non-fatally, exit 0, "N package(s) skipped (only available on arm64 macos and x86_64/arm64 linux)". One config shared by both arches would leave the 13" without those tools while `make core` reported success, which is the silent half-install the phases exist to avoid.

It could not win on Intel even if it ran: mise pours Homebrew's own bottles, so where Homebrew stopped building x86_64 there is nothing to pour, and mise has no fallback - not the older-same-arch bottle `brew` will take, and not a source build. On Intel that makes plain `brew` strictly the more capable of the two. On arm64, where it does run, it still would not retire `brew`: third-party taps publish no API metadata and get built from source through mise's Formula-DSL shim (that is all three `genkio/tap/*` formulae), cask coverage is narrow with no cask import and **no `brew services`** (which `tailscale-up.sh` and `update.sh` use), and `[bootstrap.packages]` is deliberately not `[tools]`, so `mise install` ignores it and `make core` would need a second command.

The split therefore stays: brew for bottles, casks, taps and services; mise for vendor-built binaries; a script for the three pinned outside both.

## Tailscale

The `tailscale` **formula**, not the `tailscale-app` cask, and deliberately so: this machine has to *accept* inbound Tailscale SSH, and that server component runs only on Linux and this open-source `tailscaled`. The mac app cannot serve it, so the cask is not a substitute however much tidier it looks. That decision is what keeps `scripts/tailscale-up.sh` (`make tailscale`), `scripts/tailscale-exit.sh` and `tailscale_followups()` in `update.sh` alive; do not delete them on the grounds that the app would handle it.

The costs that come with the formula, all already handled:

- It is a Go build with no Intel bottle, which is why no phase installs it: `make tailscale` does, on request.
- `tailscaled` runs as a root LaunchDaemon so the node is up without a login; `scripts/tailscale-up.sh` starts it. That daemon is the reason tailscale left `make all`: a bootstrap should not put a machine on a tailnet unasked.
- The daemon keeps running the binary it started with, and superseded kegs keep root-owned files that `brew cleanup` cannot remove. `update.sh` reports both instead of sudoing.
- Its darwin router never programs the IPv4 default route, so `tailscale set --exit-node=X` alone routes nothing. `scripts/tailscale-exit.sh` adds `0.0.0.0/1` + `128.0.0.0/1` over the tailscale utun plus an interface-scoped default via the physical gateway.

## Sublime Text

Installed as `cask "sublime-text"` in `brew/Brewfile.apps`. `scripts/setup-sublime.sh` (run by `make apps`; standalone via `make sublime`) provisions it headlessly:

- Bootstraps Package Control by downloading `Package Control.sublime-package` into `~/Library/Application Support/Sublime Text/Installed Packages/` when missing (non-fatal on network failure).
- Seeds the User `Package Control.sublime-settings` from `sublime/Package Control.sublime-settings` when absent, else merges the curated `installed_packages` into the existing file (union, preserving Package Control's runtime keys and GUI-added packages). Package Control installs listed-but-missing packages on launch.
- The merge tolerates Sublime's JSON-with-comments + trailing commas via a string-aware pre-parse in `python3` (`/usr/bin/python3` from Xcode CLT is always present once Homebrew is).
- Sets Sublime as the macOS default opener for text + code from `sublime/file-associations.txt` (UTIs + bare extensions, `#` comments). Bare extensions are resolved to UTIs by an inline `swift` snippet (`UTType(filenameExtension:)`) and `dyn.*` results dropped: an extension no installed app declares has no handler slot to set, so listing it was always a no-op. Current handler is read with `duti -d` and matches skipped, so a re-run on a provisioned machine writes nothing. Changes go in by rewriting `LSHandlers` in the `com.apple.launchservices.secure` domain (`defaults export` → `python3` `plistlib` → `defaults import`, then `killall lsd`), not via `duti -s`: the LaunchServices API pops a modal Finder confirmation per type, so a fresh machine used to stack ~30 dialogs. Do not edit that plist in place - cfprefsd caches the domain and flushes its copy back over a direct write. Bundle id is read from the app's `Info.plist` (fallback `com.sublimetext.4`). `duti` is a formula in `brew/Brewfile.apps`; absent → step skipped, non-fatal. This step runs before the package-list section so its early `exit 0`s don't skip it.
- First launch on a fresh machine bootstraps Package Control (dependency→library migration, prompts to restart); seeded packages install after one quit/reopen. Deliberately not automated: launching the GUI mid-`make` and quitting on a timer risks quitting mid-install (half-migrated syntax errors), worse than a clean manual restart. `setup-sublime.sh` prints this expectation instead.

`sublime/Package Control.sublime-settings` is the source of truth for the package list; it is **seeded, not stowed** (Package Control rewrites the live file at runtime). `sublime/.stow-local-ignore` keeps `stow sublime` a no-op. To add a package: install it via `Package Control: Install Package`, add the name to the tracked file, and re-run `make sublime` elsewhere.

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
| `hammerspoon` | `~/.hammerspoon/` | Hammerspoon config and two right-Command modules. `aerospace_leader` makes right-Command the AeroSpace leader: Carbon hotkeys carry no left/right modifier bits, so `rightCmd-h` cannot exist in `aerospace.toml`; the tap reads raw device flags, names the key and calls `trigger-binding --mode rcmd`. The keymap stays in `aerospace.toml`, and that mode is never entered. `rcmd` is the pre-AeroSpace launcher (`rcmd.config.lua`), kept for machines where AeroSpace is not running: `aerospace_leader` polls `applicationsForBundleID("bobko.aerospace")` every 2s and rcmd subscribes through `onRunningChanged`, so exactly one of the two owns right-Command at any moment. Not `hs.application.watcher`: on AeroSpace's terminated event LuaSkin fails to build an app object for the dead pid ("Unable to fetch NSRunningApplication") and the watcher goes silent for good, which is what made the first attempt look dead after quitting AeroSpace. `init.lua` loads `hs.ipc`, so `hs -c 'print(require("rcmd").isSuspended())'` shows the state from a shell. The old `toggle_fn_keys` action and `bin/fnstate.c` were not brought back |
| `aerospace` | `~/.config/aerospace/` | Tiling WM. `cask "nikitabobko/tap/aerospace"`, own tap, not homebrew-cask. The focus ring is JankyBorders (`brew "FelixKratz/formulae/borders"`), started from `after-startup-command`, which fires only when AeroSpace launches - a `reload-config` will not pick up a changed startup line, and `brew services start borders` would run a second copy. It also runs `scripts/reclaim-workspaces.sh`: AeroSpace names a workspace after the mission control space it first found a window on, so a restart strands windows on workspaces this config never mentions (a `5` on the bar next to a `1`, with no binding that reaches it). Those windows go back into the persistent set, which the script reads out of the TOML rather than repeating. Startup only - the callbacks that would catch a mid-session stray also fire on ordinary window moves, and this is not a policy worth enforcing against a deliberate one. That command is one entry, `scripts/startup.sh`, which starts the bar and then the ring: AeroSpace hands its children a Homebrew prefix of its own choosing (`/opt/homebrew/bin` here, per `aerospace list-exec-env-vars`), so a bare `sketchybar` in the TOML would resolve to nothing on an Intel Mac and never start the bar, silently. The script spells both prefixes, as every other script in the package does. Its settings live in `scripts/chrome.sh` rather than in the TOML line, because `fullscreen-toggle.sh` (rcmd-enter) has to put the ring back after hiding it, and one definition is enough. `chrome.sh` switches the ring and the sketchybar bar together: a fullscreen window wants neither, and `fullscreen --no-outer-gaps` goes with them, since a hidden bar plus the gap that made room for it reads as a stuck window. Only the fullscreen window's own display loses its bar - `chrome.sh` takes the displays that keep one and passes them to `--bar display=`, falling back to `hidden=on` when a single monitor leaves no list to draw on. The ids come from `%{monitor-appkit-nsscreen-screens-id}`, because sketchybar numbers displays the way AppKit does and AeroSpace's own `%{monitor-id}` is a different ordering that would blank the wrong screen (here: monitor-id 1 is the DELL, AppKit id 1 is the built-in). The ring is not per-display and does not need to be: it only ever draws around the focused window, which is the fullscreen one. Hiding the ring means transparent colors, not killing the process, which has no disable verb and would lose every setting on restart. AeroSpace drops fullscreen the moment the window loses focus, so `on-focus-changed` runs `sync.sh` (spaces + chrome) to follow the window's real state - otherwise the bar stays hidden with nothing fullscreen. That hook fires on every mouse-driven focus change (focus follows mouse is on), so the sync memoizes its last decision in `$TMPDIR` and only spawns sketchybar and borders on an actual transition. Both taps are pre-trusted in the `apps` phase, as `core` does for `genkio/tap`. AeroSpace, borders and sketchybar are also the three desktop entries in `Brewfile.apps` with no `unless in_vm` guard, deliberately: a VM is where this stack gets tested before it reaches a real machine. Nothing else about it is VM-aware and nothing needs to be - the menu bar write is unguarded, and the top gap is one value for every display (see below). Both are Intel-safe and neither belongs in the table above: the cask is one universal binary (`lipo -archs` gives `x86_64 arm64`, single URL, no per-arch logic), and borders is the "small C build" the Brewfile rule keeps in brew - 8 files, one `clang -O3`, only system frameworks, no `-arch` in its makefile so it builds for the host. Floors differ: AeroSpace wants macOS 13, borders 14. `sketchybar` is started from the same `after-startup-command` and fed by `exec-on-workspace-change`. `gaps.outer.top` exists because of it and is **one value for every display**, 41. The bar draws at window layer -20, *below* ordinary windows, so that gap is the only thing keeping it visible at all: a gap smaller than the bar means windows sit on top of it and the bar is simply gone. The macOS menu bar is auto-hidden (`macos-bootstrap.sh`), so a display reserves nothing at the top and the whole 40pt bar has to come out of the gap. It was per-monitor until this bit, `[{ monitor.'built-in' = 11 }, 41]`, on the reasoning that a notched built-in reserves a strip AeroSpace never tiles into - true here, `safeAreaInsets.top` measures 32 and windows landed at 43. But that pattern matches the display *name*, and a notched and a non-notched built-in both report exactly `Built-in Retina Display`, so no pattern can separate them: the Intel 13" took 11pt of clearance for a 40pt bar and came up with no visible status bar at all. The price of the uniform value falls on the notched display alone, windows starting at 32 + 41 = 73 rather than 43, so ~33pt of desktop shows under the bar. Shrinking the bar does not buy that back - where nothing is reserved the gap must clear the whole bar, so the waste always equals the reserve. Bindings are `alt`-based but the letter workspaces are dropped: Alacritty runs `option_as_alt = "Both"`, so any `alt-<key>` AeroSpace takes never reaches the terminal, and the defaults would eat `alt-a`/`alt-d` (`zsh/.zshrc`) and `alt-shift-U/D/J/K` (Claude Code scroll chords) |
| `sketchybar` | `~/.config/sketchybar/` | Status bar. `brew "FelixKratz/formulae/sketchybar"`, same tap as borders, pre-trusted in the `apps` phase. Intel-safe and staying in brew for the same reason borders does, despite having no bottle at all: its default make target builds `x86_64-apple-macos10.13` and `arm64-apple-macos11` and `lipo`s them, links only system frameworks, and takes ~6s. The bar is workspace numbers on the left, volume and clock on the right, no icons anywhere: what is left of upstream's demo is the two plugin scripts and the bar's own geometry. Started from `aerospace.toml`'s `after-startup-command`, like borders, so `brew services` stays out of it. That is the **only** launch site, and it fires only when AeroSpace itself launches, so a bar installed, stowed or killed since then stays dead however many hooks run - `borders <args>` starts a daemon when none is running, `sketchybar --bar ...` does not. Hence the liveness check at the top of `chrome-sync.sh`, ahead of the memo that would otherwise short-circuit the one call able to revive it. It skips itself on `force` and never returns early: `force` arrives from `startup.sh` one line after it spawned the bar, and from `sketchybarrc`, which *is* the bar, so a pgrep there loses the race, spawns a duplicate that bows out on the lock file, and an early return would leave borders unstarted. `startup.sh` opens by `pkill`ing both: anything alive when AeroSpace launches is stale by definition, and a bar orphaned to launchd (`PPID 1`) holds the lock file against every launch that follows, login included - a machine once came up with a sketchybar process, no bar, and nothing able to replace it. borders does not lock at all and simply stacks, 8 copies measured, which the same `pkill` reclaims. AeroSpace workspaces are not mission-control spaces, so the `space` component cannot see them: the items are plain items, one per workspace 1-9, and both the highlight and which of them draw at all arrive as the payload of a custom `aerospace_workspace_change` event. That fixed range is deliberate and replaced an `aerospace list-workspaces --all` loop: AeroSpace invents workspaces after the bar has started - restart it and windows land on one, measured - and an item that does not exist by then can never be shown without repeating its whole definition outside the rc. `scripts/spaces-sync.sh` on the AeroSpace side decides that payload - workspaces holding windows, plus the focused one even when empty, and nothing at all when only one workspace is in use - so the per-item plugin stays a string match and makes no `aerospace` calls of its own. It also carries the agent-attention state: a pane whose Claude Code or pi hook marked it `@agent_pane_state attention` (`tmux/bin/agent-attention.sh`) turns the box of the workspace holding its terminal red, outranking both the focus outline and the one-workspace rule - a box that is not drawn cannot be red. tmux is invisible to AeroSpace, so that half cannot ride the WM's callbacks: a hidden `spaces_heartbeat` item re-runs the sync every 2s (sketchybar runs the scripts of hidden items too, measured), and the sync's memo means a tick that changed nothing costs one `tmux list-panes`. The rc prepends both Homebrew prefixes to `PATH` and bakes the resolved `aerospace` path into each `click_script`: exporting is not enough, since click and plugin scripts are spawned by the sketchybar daemon with its own environment, not by the rc. It ends by calling `scripts/sync.sh force`, which covers both halves: `--update` runs the workspace scripts with no payload and the items start `drawing=off`, so nothing would appear until the first switch, and a bar that just came back from a restart is visible on every display whatever the chrome memo last recorded. `force` is what gets past both memos - they live in `$TMPDIR` and outlive the sketchybar process. The `×` at the right end is a true quit: `scripts/quit.sh` SIGTERMs AeroSpace, borders and sketchybar together, since AeroSpace has no quit verb of its own and a bar left behind has nothing to feed it. Relaunching AeroSpace alone brings the other two back, which is also why `startup.sh` ends in a forced sync rather than assuming the bar is fresh: a second sketchybar bows out on the lock file, so `sketchybarrc` would never run its own. The numbers are outlined boxes copying AeroSpace's own menu bar indicator, except for focus: AeroSpace dashes the focused workspace's border and sketchybar's item background has no dash pattern, so focus is a brighter outline plus a faint fill instead. Labels are `.AppleSystemUIFont`, the only name that reaches the macOS UI font: there is no user-facing `SF Pro` or `SF Mono` family, and asking for `"SF Pro"` silently lands on Helvetica |
| `alacritty` | `~/.config/alacritty/` | Terminal emulator (Flexoki Light / TokyoNight Storm). Run `scripts/apply-alacritty-theme.sh` after stow to seed the active theme; light/dark is driven by `theme-toggle.sh` (tmux `prefix + t`), which rewrites the active theme and repaints the running terminal via OSC |
| `mise` | `~/.config/mise/` | Polyglot version manager, split three ways (see below). Stowed by `core`, not `dev`, because `core` now needs it |
| `claude` | `~/.claude/` | Use `scripts/restore-claude-settings.sh`; the whole package is linked (`settings.json`, `statusline-command.sh`, `keybindings.json`, plus the `rules/` and `hooks/` dirs) |
| `pi` | `~/.pi/agent/` | Use `scripts/restore-pi-settings.sh`; links `settings.json`, `keybindings.json`, and `extensions/{tmux-agent-state,quiet-tools,usage-footer,deny-guard}.ts` (tmux agent-state hooks as in Claude; quiet-tools renders every tool row and thinking row at zero height until `Ctrl+O`, keeping one `✗ <tool> failed` line for errors; usage-footer replaces the footer with one line - context usage, session cost with the DeepSeek account balance, cwd, model - and halves DeepSeek off-peak pricing; deny-guard blocks the commands and paths from the Claude `permissions.deny` list and lets everything else run), installs `pi-web-access` via `pi install`, and seeds `web-search.json`. `trust.json` is machine-local, not stowed; so is `extensions/herdlet.ts`, which `scripts/link-herdlet.sh` links into the herdlet keg (see the stow section) |
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
- `~/.pi/agent/settings.json` - tracked and stowed (linked to `pi/.pi/agent/settings.json`); pi rewrites it at runtime (`/settings`, `pi install`, changelog cursor), so those writes land in the repo as changes to commit, same as `claude/.claude/settings.json`. `trust.json` stays machine-local. The tracked file must have **no trailing newline**: pi persists settings as `JSON.stringify(settings, null, 2)` with none, and a newline makes every runtime write show up as a `\ No newline at end of file` diff on fresh machines. `keybindings.json` is the opposite - pi's keybinding migration writes `${JSON.stringify(config, null, 2)}\n`, so it keeps its newline
- `~/.pi/agent/web-search.json` - machine-local pi-web-access config (search workflow, providers, keys); seeded from `pi/.pi/agent/web-search.json.example`, not stowed, because the extension rewrites it when the curator changes providers
