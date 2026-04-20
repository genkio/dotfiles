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

## Restore on a new machine

- `git clone git@github.com:yourusername/dotfiles.git ~/dotfiles && cd ~/dotfiles`
- `stow vim` or `stow git`
- Core packages: `mkdir -p ~/.ssh && chmod 700 ~/.ssh && stow brew git nvim nvim-next tmux yazi zsh ssh`
- `nvim-next` installs `~/.config/nvim-next`; launch it with `NVIM_APPNAME=nvim-next nvim` or the `vim` shell wrapper from this repo
- Optional app packages: `stow hammerspoon karabiner`
- Optional dev packages: `stow ghostty && bash scripts/restore-claude-settings.sh && bash scripts/restore-codex-config.sh`
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

- `chmod +x scripts/opinionated-flow.sh && ./scripts/opinionated-flow.sh --bootstrap-macos --include-all`
- The script also prepares `~/.ssh` and stows `ssh/.ssh/config` when `~/.ssh/config` is not already a regular file.
- The core stow step includes both `nvim` and `nvim-next`.
- `--bootstrap-macos` to run `scripts/macos-bootstrap.sh` at the end (macOS only; prompts for `sudo` and may require logout/login for some settings).
- On newer macOS releases, individual preference writes that Apple rejects are skipped with a warning so the rest of the bootstrap can continue.
- `--include-all` to install both GUI apps and dev tools.
- `--include-apps` to install GUI apps and stow `hammerspoon` and `karabiner`.
- `--include-dev` to install dev tools (sdkman-cli, claude-code, codex, version managers, etc.), restore `~/.claude`, and seed `~/.codex/config.toml` when missing.
