local M = {}

function M.setup()
  vim.keymap.set('n', '<leader>er', '<cmd>Rex<CR>', {
    desc = 'Return to explorer',
  })
end

return M
