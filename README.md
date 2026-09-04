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
- Link it into both targets: `cd ~/dotfiles && stow -R -t ~/.claude/skills skills && stow -R -t ~/.codex/skills skills`

## Restore on a new machine

- `git clone git@github.com:yourusername/dotfiles.git ~/dotfiles && cd ~/dotfiles`
- `stow vim` or `stow git`
- Core packages: `mkdir -p ~/.ssh ~/.config/mpv && chmod 700 ~/.ssh && stow brew git mpv nvim tmux vim yazi zsh ssh`
- `nvim` installs `~/.config/nvim`; launch it with `nvim`
- Optional app packages: `stow hammerspoon`, then `make sublime` to enable Sublime's Package Control and auto-install packages
- Optional dev packages: `stow alacritty && bash scripts/apply-alacritty-theme.sh && bash scripts/restore-claude-settings.sh && bash scripts/restore-codex-config.sh`
  - Both restore scripts also stow the shared `skills/` package into `~/.claude/skills/` and `~/.codex/skills/` so coding-agent skills are kept in one place.
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

## Sublime Text

Installed as a cask via `brew/Brewfile.apps`. `scripts/setup-sublime.sh` (run by `make apps` / `--include-apps`, or standalone via `make sublime`) enables Package Control headlessly, auto-installs a curated package set, and makes Sublime the default opener for text + code files:

- Bootstraps Package Control by dropping `Package Control.sublime-package` into `~/Library/Application Support/Sublime Text/Installed Packages/`.
- Seeds (or merges) `installed_packages` into that app's User settings from `sublime/Package Control.sublime-settings`; Package Control installs any listed-but-missing package on launch.
- Sets Sublime as the macOS default opener for text + code files via `duti` (from `brew/Brewfile.apps`); the type list lives in `sublime/file-associations.txt` (edit + re-run `make sublime`). Standalone `make sublime` needs `duti` present, so run `make apps` first on a new machine.
- First launch on a new machine bootstraps Package Control (one-time dependency migration; it may prompt to restart Sublime). Quit and reopen once and the listed packages install. This is Package Control's own bootstrap, unavoidable with any install method.
- To add a package: install it once (`Package Control: Install Package`), add its name to `sublime/Package Control.sublime-settings`, commit, and re-run `make sublime` on other machines.

The live settings file is seeded, not stowed: Package Control rewrites it at runtime, so a symlink into the repo would churn.

## Routine maintenance

`make update` (`scripts/update.sh`, `--dry-run` via `make update DRY_RUN=1`) keeps an already-provisioned machine current. It never installs a package the machine does not already have, never writes a macOS default, and never asks for `sudo`, so it is safe to run unattended whatever profile the machine was built with:

- `brew update && brew upgrade` for everything already installed. No `brew bundle`: that would install every entry of every Brewfile and quietly converge a base machine to `--include-all`. A package added to a Brewfile reaches other machines when you run `make apps` / `make dev` there.
- Re-runs `scripts/install-alacritty.sh`, a no-op unless its pinned `VERSION` changed, so a deliberate bump on one machine reaches the others after a pull.
- Restows every package, reporting only links that genuinely appeared, vanished, or conflicted.
- Refreshes the generated Alacritty theme cache, and seeds `~/.gitconfig.local` / `~/.codex/config.toml` when missing. When they already exist it only reports which keys the `.example` has gained since; those files hold machine-local state, so merging is left to you.
- Runs `scripts/check-pins.sh` (below).
- Warns when the checkout is behind its upstream, but never pulls: an automatic pull into a dirty tree is a worse surprise than a stale run.

Anything needing a decision is collected into one block at the end. `tailscaled` runs as a root LaunchDaemon, so upgrading its formula needs no privileges but restarting the daemon and removing the superseded root-owned keg do; `make update` reports both commands instead of asking for a password.

Deliberately left alone: mise toolchains and uv tools (a global bump buys nothing, and project-local pins resolve independently), Claude Code, Oh My Zsh, tmux and Neovim plugins (nvim's lockfile is tracked, so updating it is a repo change), Sublime packages, and macOS defaults. Rerun `scripts/macos-bootstrap.sh` deliberately for the last of those.

## Opinionated flow

Run the automated script:

- `make` (equivalent to `./scripts/opinionated-flow.sh --bootstrap-macos --include-all`)
- Other targets: `make bootstrap`, `make apps`, `make dev`, `make update`, `make ssh`, `make gpg`, `make sublime`, `make tailscale`
- `make tailscale` logs this machine into the tailnet (`scripts/tailscale-up.sh`): starts the tailscaled service if it is not responding, then runs `sudo tailscale up --ssh --operator=<you>` and prints a URL to authorize in the browser. Idempotent: it reports the current status and exits when the node is already up. Exit nodes stay separate: advertise with `sudo tailscale set --advertise-exit-node`, consume one with `scripts/tailscale-exit.sh on <node>`.
- `make ssh` defaults to GitHub; pass a host label to key it per service: `make ssh gitlab` (or `make ssh HOST=gitlab`) writes `~/.ssh/id_ed25519_gitlab` and appends a `gitlab.com` block to `~/.ssh/config`. `github`, `bitbucket`, and `gitlab` get a real hostname and paste URL; any other label is used verbatim as the hostname.
- Identity is optional and passed the same way: `make ssh gitlab EMAIL=me@example.com NAME='Genkio Ji'`. Worth setting, because the script writes the email it used into `~/.gitconfig.local`, and its default is the GitHub noreply address. Only explicit `VAR=...` on the command line is honoured, so an exported `$EMAIL`/`$NAME` in your shell cannot leak in. For `--type` and `--passphrase`, call `./scripts/generate-ssh-key.sh` directly.
- The script also prepares `~/.ssh` and stows `ssh/.ssh/config` when `~/.ssh/config` is not already a regular file.
- The core stow step installs `nvim`.
- `--bootstrap-macos` to run `scripts/macos-bootstrap.sh` at the end (macOS only; prompts for `sudo` and may require logout/login for some settings).
- Touch ID for sudo (`/etc/pam.d/sudo_local`) is written by `scripts/touchid-sudo.sh` as the very last step of the run, because from then on `sudo` asks for a fingerprint instead of taking the password the setup feeds it. Standalone: `bash scripts/touchid-sudo.sh` (`--dry-run` to preview).
- On newer macOS releases, individual preference writes that Apple rejects are skipped with a warning so the rest of the bootstrap can continue. A failed package (e.g. a `brew bundle` entry) is likewise a warning, not a stop.
- Non-fatal warnings are prefixed `SETUP_WARN:` (yellow) and fatal errors `SETUP_ERROR:` (red) across every script `make` runs, so they stand out in a long run by default (see below).
- `--include-all` to install both GUI apps and dev tools.
- `--include-apps` to install GUI apps, stow `hammerspoon`, and set up Sublime Text (Package Control + auto-installed packages).
- `--include-dev` to install dev tools (mise, codex, claude-code, etc.), restore `~/.claude`, and seed `~/.codex/config.toml` when missing.

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
