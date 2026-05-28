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
- Optional app packages: `stow hammerspoon`
- Optional dev packages: `stow ghostty && bash scripts/restore-claude-settings.sh && bash scripts/restore-codex-config.sh`
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

## Opinionated flow

Run the automated script:

- `make` (equivalent to `./scripts/opinionated-flow.sh --bootstrap-macos --include-all`)
- Other targets: `make bootstrap`, `make apps`, `make dev`, `make ssh`, `make gpg`
- The script also prepares `~/.ssh` and stows `ssh/.ssh/config` when `~/.ssh/config` is not already a regular file.
- The core stow step installs `nvim`.
- `--bootstrap-macos` to run `scripts/macos-bootstrap.sh` at the end (macOS only; prompts for `sudo` and may require logout/login for some settings).
- On newer macOS releases, individual preference writes that Apple rejects are skipped with a warning so the rest of the bootstrap can continue.
- `--include-all` to install both GUI apps and dev tools.
- `--include-apps` to install GUI apps and stow `hammerspoon`.
- `--include-dev` to install dev tools (mise, codex, claude-code, etc.), restore `~/.claude`, and seed `~/.codex/config.toml` when missing.
