# Dotfiles

Managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Setup

Clone the repo:

- `git clone git@github.com:yourusername/dotfiles.git ~/dotfiles && cd ~/dotfiles`

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

## Remove symlinks

- `stow -D vim`
