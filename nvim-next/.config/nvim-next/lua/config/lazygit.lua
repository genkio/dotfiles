local M = {}

function M.open()
  vim.cmd.tabnew()
  vim.fn.termopen({ 'lazygit' }, { cwd = vim.fn.getcwd() })
  vim.cmd.startinsert()
end

function M.setup()
  vim.api.nvim_create_user_command('LazyGit', M.open, {
    desc = 'Open LazyGit in a new tab terminal',
  })

  vim.keymap.set('n', '<leader>lg', M.open, { desc = 'LazyGit' })
end

return M
