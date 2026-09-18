local M = {}

local resolved_config_dir = vim.fn.resolve(vim.fn.stdpath 'config')
M.dotfiles_root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(resolved_config_dir)))

function M.join(...)
  return vim.fs.joinpath(M.dotfiles_root, ...)
end

return M
