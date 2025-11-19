-- custom/copy_range.lua
-- Copy selection range (or current line) with line numbers

local function copy_range_with_lines()
  local mode = vim.fn.mode()
  local start_line, end_line

  -- Use visual selection if in visual mode
  if mode:match '[vV]' then
    start_line = vim.fn.line 'v'
    end_line = vim.fn.line '.'
    if start_line > end_line then
      start_line, end_line = end_line, start_line
    end
  else
    start_line = vim.fn.line '.'
    end_line = start_line
  end

  local total = vim.api.nvim_buf_line_count(0)

  -- Prefer relative path to cwd unless it goes through ..
  local rel = vim.fn.expand '%:.'
  local fn
  if rel ~= '' and not rel:match '^%.%.' then
    fn = rel
  else
    fn = vim.fn.expand '%:t'
  end
  if fn == '' then
    fn = '[No Name]'
  end

  local out
  if start_line == 1 and end_line == 1 then
    out = fn
  elseif start_line == total and end_line == total then
    out = string.format('%s:1-%d', fn, total)
  else
    out = string.format('%s:%d-%d', fn, start_line, end_line)
  end

  -- Copy to unnamed register
  vim.fn.setreg('"', out)

  local ok, osc52 = pcall(require, 'osc52')
  if ok then
    osc52.copy(out)
  else
    pcall(vim.fn.setreg, '+', out)
  end

  vim.notify('Copied: ' .. out)
end

-- Keymap for normal + visual mode
vim.keymap.set({ 'n', 'v' }, '<leader>yr', copy_range_with_lines, {
  desc = 'Copy selection range to clipboard (with line numbers)',
})
