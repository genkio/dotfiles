# Dotfiles

Managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Setup

Clone the repo:

- `git clone https://github.com/genkio/dotfiles.git && cd ~/dotfiles`

Install stow:

- macOS: `brew install stow`
- Debian/Ubuntu: `sudo apt install stow`

## Add a new dotfile

- `mkdir -p ~/dotfiles/vim`
- `mv ~/.vimrc ~/dotfiles/vim/`
- `cd ~/dotfiles && stow vim`
  Creates: `~/.vimrc -> ~/dotfiles/vim/.vimrc`

## Restore on a new machine

- `git clone git@github.com:yourusername/dotfiles.git ~/dotfiles && cd ~/dotfiles`
- `stow vim` or `stow git`
- Or everything after creating `~/.ssh`: `mkdir -p ~/.ssh && chmod 700 ~/.ssh && stow */`
- Lazygit: macOS `stow lazygit`; Linux `stow --ignore='^Library/' lazygit`
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

- `chmod +x scripts/opinionated-flow.sh && ./scripts/opinionated-flow.sh --bootstrap-macos --include-dev --include-apps`
- The script also prepares `~/.ssh` and stows `ssh/.ssh/config` when `~/.ssh/config` is not already a regular file.
- `--bootstrap-macos` to run `scripts/macos-bootstrap.sh` at the end (macOS only; prompts for `sudo` and may require logout/login for some settings).
- `--include-apps` to install GUI apps too.
- `--include-dev` to install dev tools (lazygit, sdkman-cli, claude-code, codex, version managers, etc.), restore `~/.claude`, and seed `~/.codex/config.toml` when missing.
