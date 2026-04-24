local M = {}

local function current_word()
  local word = vim.fn.expand '<cword>'
  return word ~= '' and word or nil
end

local function clear_window_match(win)
  local id = vim.w[win].nvim_next_cursorword_match_id
  if id then
    pcall(vim.fn.matchdelete, id, win)
    vim.w[win].nvim_next_cursorword_match_id = nil
  end
end

function M.clear_cursor_word()
  clear_window_match(vim.api.nvim_get_current_win())
end

function M.highlight_cursor_word()
  local win = vim.api.nvim_get_current_win()
  clear_window_match(win)

  if vim.bo[vim.api.nvim_win_get_buf(win)].buftype ~= '' then
    return
  end

  local word = current_word()
  if not word then
    return
  end

  local pattern = '\\V\\<' .. vim.fn.escape(word, '\\') .. '\\>'
  local id = vim.fn.matchadd('NvimNextCursorWord', pattern, 10, -1, { window = win })
  if id and id > 0 then
    vim.w[win].nvim_next_cursorword_match_id = id
  end
end

function M.setup()
  vim.api.nvim_set_hl(0, 'NvimNextCursorWord', { link = 'Search' })

  local group = vim.api.nvim_create_augroup('nvim-next-search-highlight', { clear = true })

  vim.api.nvim_create_autocmd({ 'CursorMoved', 'InsertEnter', 'WinLeave' }, {
    group = group,
    callback = function()
      M.clear_cursor_word()
    end,
  })

  vim.api.nvim_create_autocmd({ 'CursorHold', 'BufEnter', 'WinEnter' }, {
    group = group,
    callback = function()
      M.highlight_cursor_word()
    end,
  })

  vim.keymap.set('n', '<Esc>', function()
    M.clear_cursor_word()
    vim.cmd.nohlsearch()
  end, {
    silent = true,
    desc = 'Clear search highlight',
  })
end

return M
