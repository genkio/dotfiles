-- Resolve the dotfiles repo root from the (possibly symlinked) Neovim config
-- dir, so modules never hardcode ~/dotfiles. Stow links ~/.config/nvim to
-- <root>/nvim/.config/nvim, so three parents up from the resolved config dir
-- is the repo root.

local M = {}

local resolved_config_dir = vim.fn.resolve(vim.fn.stdpath 'config')
M.dotfiles_root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(resolved_config_dir)))

-- Join path segments onto the dotfiles root, e.g. join('tmux', 'bin', 'x.sh').
function M.join(...)
  return vim.fs.joinpath(M.dotfiles_root, ...)
end

return M
