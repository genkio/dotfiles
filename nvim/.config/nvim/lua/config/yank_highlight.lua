local M = {}

function M.setup()
  local group = vim.api.nvim_create_augroup('nvim-next-yank-highlight', { clear = true })

  vim.api.nvim_create_autocmd('TextYankPost', {
    group = group,
    callback = function()
      vim.hl.on_yank { timeout = 200 }
    end,
  })
end

return M
