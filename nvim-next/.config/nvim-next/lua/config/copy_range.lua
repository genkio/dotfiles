local M = {}

local function visual_range()
  local start_line = vim.fn.line 'v'
  local end_line = vim.fn.line '.'

  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end

  return start_line, end_line
end

local function current_range()
  local line = vim.fn.line '.'
  return line, line
end

local function resolve_range()
  local mode = vim.fn.mode()
  if mode:match '[vV]' then
    return visual_range()
  end

  return current_range()
end

local function relative_path(bufnr)
  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == '' then
    return '[No Name]'
  end

  local absolute = vim.fs.normalize(path)
  local root = vim.fs.root(absolute, { '.git' }) or vim.uv.cwd() or vim.fn.getcwd()
  local relative = vim.fs.relpath(root, absolute)

  return relative or vim.fn.fnamemodify(absolute, ':t')
end

function M.build(bufnr)
  bufnr = bufnr or 0

  local path = relative_path(bufnr)
  local start_line, end_line = resolve_range()
  local total = vim.api.nvim_buf_line_count(bufnr)

  if start_line == 1 and end_line == total then
    return path
  end

  return string.format('%s:%d-%d', path, start_line, end_line)
end

function M.copy()
  local text = M.build(0)

  vim.fn.setreg('"', text)
  vim.fn.setreg('+', text)

  vim.notify('Copied: ' .. text)
end

function M.setup()
  vim.keymap.set({ 'n', 'v' }, '<leader>yr', M.copy, {
    desc = 'Copy selection range to clipboard',
  })
end

return M
