local M = {}

function M.quit_all()
  local has_unsaved = false
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].modified and vim.bo[buf].buflisted and vim.bo[buf].buftype == '' then
      has_unsaved = true
      break
    end
  end

  if not has_unsaved then
    vim.cmd 'qa!'
    return
  end

  local choice = vim.fn.confirm('Unsaved changes. Quit anyway?', '&Save all\n&Discard\n&Cancel', 3)

  if choice == 1 then
    pcall(vim.cmd, 'wall')
    vim.cmd 'qa!'
  elseif choice == 2 then
    vim.cmd 'qa!'
  end
end

function M.setup()
  vim.api.nvim_create_user_command('QuitAll', M.quit_all, {
    desc = 'Quit Neovim (prompts on unsaved buffers)',
  })

  vim.keymap.set('n', 'Q', M.quit_all, { desc = 'Quit all (prompts on unsaved buffers)' })
end

return M
