local M = {}

function M.setup()
  vim.g.netrw_liststyle = 3

  vim.keymap.set('n', '<leader>er', '<cmd>Rex<CR>', {
    desc = 'Return to explorer',
  })
end

return M
