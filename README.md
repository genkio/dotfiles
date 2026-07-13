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

## Opinionated flow

Run the automated script:

- `make` (equivalent to `./scripts/opinionated-flow.sh --bootstrap-macos --include-all`)
- Other targets: `make bootstrap`, `make apps`, `make dev`, `make ssh`, `make gpg`, `make sublime`
- The script also prepares `~/.ssh` and stows `ssh/.ssh/config` when `~/.ssh/config` is not already a regular file.
- The core stow step installs `nvim`.
- `--bootstrap-macos` to run `scripts/macos-bootstrap.sh` at the end (macOS only; prompts for `sudo` and may require logout/login for some settings).
- On newer macOS releases, individual preference writes that Apple rejects are skipped with a warning so the rest of the bootstrap can continue. A failed package (e.g. a `brew bundle` entry) is likewise a warning, not a stop.
- Non-fatal warnings are prefixed `SETUP_WARN:` and fatal errors `SETUP_ERROR:` across every script `make` runs, so they are easy to spot in a long run (see below).
- `--include-all` to install both GUI apps and dev tools.
- `--include-apps` to install GUI apps, stow `hammerspoon`, and set up Sublime Text (Package Control + auto-installed packages).
- `--include-dev` to install dev tools (mise, codex, claude-code, etc.), restore `~/.claude`, and seed `~/.codex/config.toml` when missing.

### Spotting warnings and errors

Warnings and errors go to stderr, so fold it into stdout with `2>&1` to catch them. This runs the setup in the foreground with all output intact and just highlights the tagged lines in color:

```sh
make 2>&1 | grep --line-buffered --color=always -E 'SETUP_WARN|SETUP_ERROR|$'
```

The trailing `|$` matches every line, so nothing is filtered out; only `SETUP_WARN:` / `SETUP_ERROR:` get colored. To review after the fact instead, tee to a log and grep it: `make 2>&1 | tee setup.log`, then `grep SETUP_ setup.log`.
