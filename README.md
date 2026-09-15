# Dotfiles

macOS only. Managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Setup

Clone the repo:

- `git clone https://github.com/genkio/dotfiles.git && cd ~/dotfiles`

Install stow:

- `brew install stow`

## Add a new dotfile

- `mkdir -p ~/dotfiles/vim`
- `mv ~/.vimrc ~/dotfiles/vim/`
- `cd ~/dotfiles && stow vim`
  Creates: `~/.vimrc -> ~/dotfiles/vim/.vimrc`

## Add a new coding-agent skill

- Drop the skill at `skills/<skill-name>/SKILL.md` (folder name must match the `name:` field).
- Link it into both targets: `cd ~/dotfiles && stow -R -t ~/.claude/skills skills && stow -R -t ~/.pi/agent/skills skills`

## Restore on a new machine

- `git clone git@github.com:yourusername/dotfiles.git ~/dotfiles && cd ~/dotfiles`
- `stow vim` or `stow git`
- Core packages: `mkdir -p ~/.ssh ~/.config/mpv && chmod 700 ~/.ssh && stow brew git mpv nvim tmux vim yazi zsh ssh`
- `nvim` installs `~/.config/nvim`; launch it with `nvim`
- Optional app packages: `stow hammerspoon`, then `make sublime` to enable Sublime's Package Control and auto-install packages
- Optional dev packages: `stow alacritty && bash scripts/apply-alacritty-theme.sh && bash scripts/restore-claude-settings.sh && bash scripts/restore-pi-settings.sh`
  - Both restore scripts also stow the shared `skills/` package into `~/.claude/skills/` and `~/.pi/agent/skills` so coding-agent skills are kept in one place. The Pi script also links `settings.json` (fullscreen TUI and other choices), the transcript keybindings, the tmux agent-state extension, `quiet-tools.ts` (renders every tool row and thinking row at zero height until `Ctrl+O`, keeping one `✗ <tool> failed` line for errors), `deny-guard.ts` (deny-only gate: the commands and paths from the Claude `permissions.deny` list are blocked, everything else runs), and `usage-footer.ts` (one-line footer: model, context usage, cwd, session cost; DeepSeek off-peak requests are priced at half, which pi's model catalog does not do) into `~/.pi/agent/`, installs the `pi-web-access` package through `pi install`, and seeds `~/.pi/agent/web-search.json` (browser curator off) from the tracked example.
- Yazi: `stow yazi`

## Remove symlinks

- `stow -D vim`

## Homebrew (optional)

Install everything (base + apps):

- `brew bundle --file brew/Brewfile`

Only base:

- `brew bundle --file brew/Brewfile.base`

Only apps:

- `brew bundle --file brew/Brewfile.apps`

Only dev tools:

- `brew bundle --file brew/Brewfile.dev`

Some things are deliberately not in any Brewfile, because Homebrew stopped
building x86_64 bottles and those formulae compile LLVM, Rust or Go first on an
Intel Mac. `mise` comes from `scripts/install-mise.sh`; `neovim`, `yazi`, `fzf`,
`fastfetch` and `sevenzip` from `mise/.config/mise/conf.d/cli.toml`, which
`make core` installs alongside the base Brewfile; and `gh` and `pi` from
`conf.d/dev.toml`. They arrive at the same versions Homebrew ships, as each
project's own release binary.

## Sublime Text

Installed as a cask via `brew/Brewfile.apps`. `scripts/setup-sublime.sh` (run by `make apps`, or standalone via `make sublime`) enables Package Control headlessly, auto-installs a curated package set, and makes Sublime the default opener for text + code files:

- Bootstraps Package Control by dropping `Package Control.sublime-package` into `~/Library/Application Support/Sublime Text/Installed Packages/`.
- Seeds (or merges) `installed_packages` into that app's User settings from `sublime/Package Control.sublime-settings`; Package Control installs any listed-but-missing package on launch.
- Sets Sublime as the macOS default opener for text + code files; the type list lives in `sublime/file-associations.txt` (edit + re-run `make sublime`). Reads the current handler with `duti` (from `brew/Brewfile.apps`), so standalone `make sublime` needs `duti` present - run `make apps` first on a new machine. Only types that differ are written, so a re-run on a provisioned machine changes nothing.
  - It writes them into the LaunchServices handler table (`defaults export`/`import` on `com.apple.launchservices.secure`, then `killall lsd`) rather than calling `duti -s`. macOS makes the user confirm every handler change that goes through the LaunchServices API, one modal Finder dialog per type, which on a fresh machine meant ~30 stacked dialogs over the terminal.
- First launch on a new machine bootstraps Package Control (one-time dependency migration; it may prompt to restart Sublime). Quit and reopen once and the listed packages install. This is Package Control's own bootstrap, unavoidable with any install method.
- To add a package: install it once (`Package Control: Install Package`), add its name to `sublime/Package Control.sublime-settings`, commit, and re-run `make sublime` on other machines.

The live settings file is seeded, not stowed: Package Control rewrites it at runtime, so a symlink into the repo would churn.

## Routine maintenance

`make update` (`scripts/update.sh`, `--dry-run` via `make update DRY_RUN=1`) keeps an already-provisioned machine current. It never installs a package the machine does not already have, never writes a macOS default, and never asks for `sudo`, so it is safe to run unattended whatever profile the machine was built with:

- `brew update && brew upgrade` for everything already installed. No `brew bundle`: that would install every entry of every Brewfile and quietly converge a base machine to everything at once. A package added to a Brewfile reaches other machines when you run `make apps` / `make dev` there.
- Upgrades mise itself, then every tool declared in `mise/.config/mise/conf.d/` (the six core CLI tools, plus `gh`, `pi`, `ctx7` and `@playwright/cli`). `config.toml` is the frozen set and is left alone: node, python, go, uv and the typescript pair. The rule is that everything in `conf.d/` was a Homebrew formula that `brew upgrade` kept current until Intel lost its bottles, so this is that job rather than a new one. Never `--bump`, so the deliberate `@playwright/cli` pin cannot move by accident.
- Re-runs `scripts/install-alacritty.sh` and `scripts/install-fliqlo.sh`, each a no-op unless its pinned `VERSION` changed, so a deliberate bump on one machine reaches the others after a pull.
- Restows every package, reporting only links that genuinely appeared, vanished, or conflicted.
- Refreshes the generated Alacritty theme cache, and seeds `~/.gitconfig.local` / `~/.pi/agent/web-search.json` when missing. When they already exist it only reports which keys the `.example` has gained since; those files hold machine-local state, so merging is left to you.
- Runs `scripts/check-pins.sh` (below).
- Warns when the checkout is behind its upstream, but never pulls: an automatic pull into a dirty tree is a worse surprise than a stale run.

Anything needing a decision is collected into one block at the end. `tailscaled` runs as a root LaunchDaemon, so upgrading its formula needs no privileges but restarting the daemon and removing the superseded root-owned keg do; `make update` reports both commands instead of asking for a password.

Deliberately left alone: mise toolchains and uv tools (a global bump buys nothing, and project-local pins resolve independently), Claude Code, Oh My Zsh, tmux and Neovim plugins (nvim's lockfile is tracked, so updating it is a repo change), Sublime packages, and macOS defaults. Rerun `scripts/macos-bootstrap.sh` deliberately for the last of those.

## Opinionated flow

Clone the repo yourself, then run the phase you want. The script operates on its
own checkout and never clones:

```bash
git clone https://github.com/genkio/dotfiles ~/dotfiles && cd ~/dotfiles && make
```

A bare `make` opens a checkbox list of the phases rather than running anything:
`↑↓`/`jk` to move, space to toggle, `a` all, `n` none, Enter to run the ticked
ones in one process, `q` to quit. Everything starts ticked, so Enter straight
away is the old meaning of `make`. Name the phases directly (`make macos`) and
it skips the menu; with no terminal to prompt on it prints the target names and
exits rather than hanging.

- Phase targets, each runnable on its own: `make macos`, `make core`, `make apps`, `make dev`, `make touchid`. `make all` runs all five in one process (one password prompt); `make bootstrap` is `macos` + `core` + `touchid`.
- Start a new machine with `make macos`: it turns off the macOS automatic update that would otherwise eat the uplink for the rest of the run, enables Remote Login, and prints the local IP so you can drive the slower phases over ssh. It installs nothing at all: no Homebrew, and no Xcode Command Line Tools either, since cloning this repo already pulled those in (`/usr/bin/git` is a CLT shim). It only checks they are there, because the Dock and screen-saver steps need `/usr/bin/python3`.
- Every run ends with a per-phase wall-clock summary, so a slow phase is visible rather than inferred.
- Other targets: `make update`, `make ssh`, `make gpg`, `make sublime`, `make tailscale`
- `make tailscale` puts this machine on the tailnet (`scripts/tailscale-up.sh`): installs the formula if missing, starts the tailscaled service if it is not responding, then runs `sudo tailscale up --ssh --operator=<you>` and prints a URL to authorize in the browser. Idempotent: it reports the current status and exits when the node is already up. Exit nodes stay separate: advertise with `sudo tailscale set --advertise-exit-node`, consume one with `scripts/tailscale-exit.sh on <node>`. This is the `tailscale` formula rather than the mac app on purpose, because only the open-source `tailscaled` can *accept* Tailscale SSH.
- `make ssh` defaults to GitHub; pass a host label to key it per service: `make ssh gitlab` (or `make ssh HOST=gitlab`) writes `~/.ssh/id_ed25519_gitlab` and appends a `gitlab.com` block to `~/.ssh/config`. `github`, `bitbucket`, and `gitlab` get a real hostname and paste URL; any other label is used verbatim as the hostname.
- Identity is optional and passed the same way: `make ssh gitlab EMAIL=me@example.com NAME='Genkio Ji'`. Worth setting, because the script writes the email it used into `~/.gitconfig.local`, and its default is the GitHub noreply address. Only explicit `VAR=...` on the command line is honoured, so an exported `$EMAIL`/`$NAME` in your shell cannot leak in. For `--type` and `--passphrase`, call `./scripts/generate-ssh-key.sh` directly.
- The script also prepares `~/.ssh` and stows `ssh/.ssh/config` when `~/.ssh/config` is not already a regular file.
- `make core` installs both package managers it needs: Homebrew for `brew/Brewfile.base`, and mise for the five CLI tools in `mise/.config/mise/conf.d/cli.toml` (neovim, yazi, fzf, fastfetch, sevenzip). Those five are on mise because on an Intel Mac their formulae compile, and yazi pulls in Rust, which pulls in LLVM. With them moved, the only thing `core` still builds from source on Intel is `tmux`.
- Touch ID for sudo (`/etc/pam.d/sudo_local`) is written by `scripts/touchid-sudo.sh` as the very last step of the run, because from then on `sudo` asks for a fingerprint instead of taking the password the setup feeds it. Standalone: `bash scripts/touchid-sudo.sh` (`--dry-run` to preview).
- On newer macOS releases, individual preference writes that Apple rejects are skipped with a warning so the rest of the bootstrap can continue. A failed package (e.g. a `brew bundle` entry) is likewise a warning, not a stop.
- Non-fatal warnings are prefixed `SETUP_WARN:` (yellow) and fatal errors `SETUP_ERROR:` (red) across every script `make` runs, so they stand out in a long run by default (see below).
- `make apps` installs GUI apps, stows `hammerspoon`, and sets up Sublime Text (Package Control + auto-installed packages).
- `make dev` installs dev tools (mise, pi, claude-code, etc.) and restores `~/.claude` and `~/.pi`.
- There is no `make heavy`. It existed because on an Intel Mac ffmpeg, mpv, tailscale and mole were the largest build graph in the repo and nothing else depended on them. Once mpv was replaced by the IINA cask on Intel, that phase was no longer the longest wait - `core` is - so its contents went where they belong: `ffmpeg` to `make dev`, `mpv` (IINA on Intel) to `make apps`, and `tailscale` to `make tailscale`, which now installs the formula as well as starting its daemon. `mole` was dropped; nothing here used it.

### Spotting warnings and errors

Run in the foreground and `SETUP_WARN:` / `SETUP_ERROR:` lines are colored automatically, so no piping is needed to see them go by.

To keep a copy for later, tee to a log (color is dropped when output is not a terminal, so the file stays clean), then grep by prefix:

```sh
make 2>&1 | tee setup.log
grep SETUP_ setup.log        # warnings + errors
grep SETUP_WARN setup.log    # non-fatal only
grep SETUP_ERROR setup.log   # fatal only
```

Warnings and errors go to stderr, hence the `2>&1`. To watch only the problems scroll by live (hides normal progress), pipe straight to grep: `make 2>&1 | grep SETUP_`.
