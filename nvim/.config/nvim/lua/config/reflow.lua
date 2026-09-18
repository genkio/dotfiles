local M = {}

local function is_blank(line)
  return line:match '^%s*$' ~= nil
end

local function is_fence(line)
  return line:match '^%s*```' ~= nil or line:match '^%s*~~~' ~= nil
end

local function is_list_item(line)
  return line:match '^%s*[%-%*%+]%s' ~= nil or line:match '^%s*%d+[%.%)]%s' ~= nil
end

local function is_atomic(line)
  return line:match '^%s*#+%s' ~= nil
    or line:match '^%s*>' ~= nil
    or line:match '^%s*|' ~= nil
    or line:match '^%s*%-%-%-+%s*$' ~= nil
    or line:match '^%s*%*%*%*+%s*$' ~= nil
    or line:match '^%s*___+%s*$' ~= nil
end

local function rtrim(s)
  return (s:gsub('%s+$', ''))
end

local function trim(s)
  return (s:gsub('^%s*(.-)%s*$', '%1'))
end

function M.unwrap(lines)
  local out = {}
  local buf = nil
  local in_fence = false

  local function flush()
    if buf ~= nil then
      out[#out + 1] = rtrim(buf)
      buf = nil
    end
  end

  for _, line in ipairs(lines) do
    if in_fence then
      out[#out + 1] = line
      if is_fence(line) then
        in_fence = false
      end
    elseif is_fence(line) then
      flush()
      out[#out + 1] = line
      in_fence = true
    elseif is_blank(line) then
      flush()
      if #out == 0 or out[#out] ~= '' then
        out[#out + 1] = ''
      end
    elseif is_list_item(line) then
      flush()
      buf = rtrim(line)
    elseif is_atomic(line) then
      flush()
      out[#out + 1] = rtrim(line)
    else
      if buf == nil then
        buf = rtrim(line)
      else
        buf = buf .. ' ' .. trim(line)
      end
    end
  end
  flush()

  return out
end

function M.reflow()
  local start_line = vim.fn.line 'v'
  local end_line = vim.fn.line '.'
  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end

  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)

  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  local replaced = M.unwrap(lines)
  vim.api.nvim_buf_set_lines(0, start_line - 1, end_line, false, replaced)
end

function M.setup()
  vim.keymap.set('x', '<leader>r', M.reflow, {
    desc = 'Reflow: unwrap hard-wrapped selection',
  })
end

return M
