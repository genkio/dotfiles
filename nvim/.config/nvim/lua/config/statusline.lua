local M = {}

function M.setup()
  -- no statusline; path/line/total/progress on demand via Ctrl-G
  vim.o.laststatus = 0
  vim.o.cmdheight = 0
end

return M
