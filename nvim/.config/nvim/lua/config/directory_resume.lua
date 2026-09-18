local M = {}

local group = vim.api.nvim_create_augroup('directory-resume', { clear = true })

local function normalize(path)
  return vim.fs.normalize(vim.fn.fnamemodify(path, ':p'))
end

local function startup_directory()
  if #vim.v.argf ~= 1 then
    return nil
  end

  local path = normalize(vim.v.argf[1])
  if vim.fn.isdirectory(path) == 0 then
    return nil
  end

  return path
end

local function state_file(root)
  local state_dir = vim.fs.joinpath(vim.fn.stdpath 'state', 'directory-resume')
  return vim.fs.joinpath(state_dir, vim.fn.sha256(root) .. '.txt')
end

local function is_descendant(root, path)
  return path == root or vim.startswith(path, root .. '/')
end

local function current_file()
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].buftype ~= '' or not vim.bo[buf].buflisted then
    return nil
  end

  local path = vim.api.nvim_buf_get_name(buf)
  if path == '' then
    return nil
  end

  path = normalize(path)
  if vim.fn.filereadable(path) == 0 then
    return nil
  end

  return path
end

local function restore_last_file(root)
  local file = state_file(root)
  if vim.fn.filereadable(file) == 0 then
    return
  end

  local lines = vim.fn.readfile(file)
  local target = lines[1]
  if not target or target == '' then
    return
  end

  target = normalize(target)
  if vim.fn.filereadable(target) == 0 or not is_descendant(root, target) then
    return
  end

  vim.schedule(function()
    vim.cmd.edit(vim.fn.fnameescape(target))
  end)
end

local function save_last_file(root)
  local target = current_file()
  if not target or not is_descendant(root, target) then
    return
  end

  local file = state_file(root)
  vim.fn.mkdir(vim.fn.fnamemodify(file, ':h'), 'p')
  vim.fn.writefile({ target }, file)
end

function M.setup()
  local root = startup_directory()
  if not root then
    return
  end

  vim.api.nvim_create_autocmd('VimEnter', {
    group = group,
    once = true,
    callback = function()
      restore_last_file(root)
    end,
  })

  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = group,
    callback = function()
      save_last_file(root)
    end,
  })
end

return M
