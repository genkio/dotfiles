local M = {}

local function can_checktime()
  return vim.fn.getcmdwintype() == ''
end

function M.checktime()
  if can_checktime() then
    vim.cmd.checktime()
  end
end

function M.setup()
  vim.o.autoread = true

  local group = vim.api.nvim_create_augroup('nvim-next-auto-reload', { clear = true })

  vim.api.nvim_create_autocmd({ 'FocusGained', 'TermClose', 'TermLeave', 'BufEnter', 'CursorHold' }, {
    group = group,
    desc = 'Reload files changed outside of Neovim',
    callback = function(event)
      if vim.bo[event.buf].buftype == '' then
        M.checktime()
      end
    end,
  })

  vim.api.nvim_create_autocmd('FileChangedShellPost', {
    group = group,
    desc = 'Notify when a file is reloaded from disk',
    callback = function()
      vim.notify('File changed on disk. Buffer reloaded.', vim.log.levels.INFO, {
        title = 'AutoReload',
      })
    end,
  })
end

return M
