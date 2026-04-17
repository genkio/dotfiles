local M = {}

function M.setup()
  vim.o.laststatus = 3
  vim.o.statusline = '%<%f%=%l:%c'
end

return M
