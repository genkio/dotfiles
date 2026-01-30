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

  -- Get absolute path of current file
  local abs_path = vim.fn.expand '%:p'
  if abs_path == '' then
    abs_path = '[No Name]'
  end

  -- Find git root, fall back to cwd
  local git_root = vim.fn.systemlist('git -C ' .. vim.fn.shellescape(vim.fn.expand '%:p:h') .. ' rev-parse --show-toplevel')[1]
  local root
  if vim.v.shell_error == 0 and git_root and git_root ~= '' then
    root = git_root
  else
    root = vim.fn.getcwd()
  end

  -- Make path relative to root
  local fn
  if abs_path:sub(1, #root) == root then
    fn = abs_path:sub(#root + 2) -- +2 to skip the trailing slash
  else
    fn = vim.fn.expand '%:t' -- fallback to just filename
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
