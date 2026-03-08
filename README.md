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
- Or everything: `stow */`
- Lazygit: macOS `stow lazygit`; Linux `stow --ignore='^Library/' lazygit`
- Yazi: `stow yazi`

## Git config

- Shared Git settings live in `git/.gitconfig`.
- Private identity lives in `~/.gitconfig.local`.
- `git/.gitconfig.local.example` is a template only; `stow git` does not symlink it into `$HOME`.
- Copy `git/.gitconfig.local.example` to `~/.gitconfig.local`, or let `scripts/opinionated-flow.sh` seed it automatically.

## Remove symlinks

- `stow -D vim`

## Homebrew (optional)

Install everything (base + apps):

- `brew bundle --file brew/Brewfile`

Only base:

- `brew bundle --file brew/Brewfile.base`

Only apps:

- `brew bundle --file brew/Brewfile.apps`

## Opinionated flow

Run the automated script:

- `chmod +x scripts/opinionated-flow.sh && ./scripts/opinionated-flow.sh --bootstrap-macos --include-apps`
- `--bootstrap-macos` to run `scripts/macos-bootstrap.sh` at the end (macOS only; prompts for `sudo` and may require logout/login for some settings).
- `--include-apps` to install apps too.

## Yazi

- `brew/Brewfile.base` installs `yazi`.
- `stow yazi` links shared config into `~/.config/yazi` and `~/.config/yazi-mobile`.
- Plain shell `yazi` uses `~/.config/yazi`.
- `yazi.nvim` reuses the same shared config and switches to `~/.config/yazi-mobile` on narrow Neovim UIs.
