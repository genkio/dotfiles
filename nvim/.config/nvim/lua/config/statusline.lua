local M = {}

function M.setup()
  vim.o.laststatus = 3
  vim.o.cmdheight = 0
  vim.o.statusline = '%<%f%=%l:%c'
end

return M
