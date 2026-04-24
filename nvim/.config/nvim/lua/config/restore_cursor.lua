local M = {}

local group = vim.api.nvim_create_augroup('nvim-next-restore-cursor', { clear = true })

local ignored_filetypes = {
  gitcommit = true,
  gitrebase = true,
  xxd = true,
}

local function should_restore(buf)
  if vim.bo[buf].buftype ~= '' or vim.wo.diff then
    return false
  end

  return not ignored_filetypes[vim.bo[buf].filetype]
end

function M.setup()
  vim.api.nvim_create_autocmd('BufReadPost', {
    group = group,
    desc = 'Restore the last cursor position for normal file buffers',
    callback = function(args)
      if not should_restore(args.buf) then
        return
      end

      local mark = vim.api.nvim_buf_get_mark(args.buf, '"')
      local line = mark[1]
      if line < 1 or line > vim.api.nvim_buf_line_count(args.buf) then
        return
      end

      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end,
  })
end

return M
