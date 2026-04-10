local M = {}

local function current_word()
  local word = vim.fn.expand '<cword>'
  return word ~= '' and word or nil
end

function M.highlight_current_word()
  local word = current_word()
  if not word then
    vim.notify('No word under cursor', vim.log.levels.WARN)
    return
  end

  local pattern = '\\V\\<' .. vim.fn.escape(word, '\\') .. '\\>'
  vim.fn.setreg('/', pattern)
  vim.v.searchforward = 1
  vim.o.hlsearch = true
end

function M.setup()
  vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>', {
    desc = 'Clear search highlight',
  })

  vim.keymap.set('n', '<leader>sh', M.highlight_current_word, {
    desc = 'Highlight current word',
  })
end

return M
