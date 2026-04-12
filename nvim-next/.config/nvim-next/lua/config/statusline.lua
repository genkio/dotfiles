local M = {}

local function git_output(root, args)
  local cmd = { 'git', '-C', root }
  vim.list_extend(cmd, args)

  local result = vim.system(cmd, { text = true }):wait()
  if result.code ~= 0 then
    return nil
  end

  local output = vim.trim(result.stdout or '')
  return output ~= '' and output or nil
end

local function git_ok(root, args)
  local cmd = { 'git', '-C', root }
  vim.list_extend(cmd, args)
  return vim.system(cmd, { text = true }):wait().code == 0
end

local function repo_root(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name ~= '' then
    return vim.fs.root(vim.fs.normalize(name), { '.git' })
  end

  local cwd = vim.uv.cwd() or vim.fn.getcwd()
  return vim.fs.root(cwd, { '.git' })
end

local function change_summary(root)
  if not git_output(root, { 'status', '--porcelain' }) then
    return ''
  end

  if not git_ok(root, { 'rev-parse', '--verify', 'HEAD' }) then
    return ' x'
  end

  local cmd = { 'git', '-C', root, 'diff', '--numstat', '--no-renames', 'HEAD', '--' }
  local result = vim.system(cmd, { text = true }):wait()
  if result.code ~= 0 then
    return ' x'
  end

  local additions = 0
  local deletions = 0

  for line in (result.stdout or ''):gmatch '[^\r\n]+' do
    local added, removed = line:match '^(%S+)%s+(%S+)'
    if added and added ~= '-' then
      additions = additions + tonumber(added)
    end
    if removed and removed ~= '-' then
      deletions = deletions + tonumber(removed)
    end
  end

  if additions > 0 or deletions > 0 then
    return string.format(' +%d,-%d', additions, deletions)
  end

  return ' x'
end

local function set_branch(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local root = repo_root(bufnr)
  local branch = ''
  local summary = ''

  if root then
    branch = git_output(root, { 'branch', '--show-current' })
      or git_output(root, { 'rev-parse', '--short', 'HEAD' })
      or ''
    summary = branch ~= '' and change_summary(root) or ''
  end

  vim.b[bufnr].nvim_next_git_branch = branch
  vim.b[bufnr].nvim_next_git_summary = summary
end

local function refresh_current_buffer()
  set_branch(vim.api.nvim_get_current_buf())
  vim.cmd.redrawstatus()
end

local function refresh_visible_buffers()
  local seen = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local bufnr = vim.api.nvim_win_get_buf(win)
    if not seen[bufnr] then
      seen[bufnr] = true
      set_branch(bufnr)
    end
  end
  vim.cmd.redrawstatus()
end

function M.branch()
  local branch = vim.b.nvim_next_git_branch
  if not branch or branch == '' then
    return ''
  end

  local summary = vim.b.nvim_next_git_summary or ''
  return '[' .. branch .. summary .. '] '
end

function M.setup()
  vim.o.laststatus = 3
  vim.o.statusline = "%{%v:lua.require'config.statusline'.branch()%}%<%f%=%l:%c"

  local group = vim.api.nvim_create_augroup('nvim-next-statusline', { clear = true })

  vim.api.nvim_create_autocmd({ 'VimEnter', 'FocusGained', 'DirChanged' }, {
    group = group,
    callback = refresh_visible_buffers,
  })

  vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWritePost' }, {
    group = group,
    callback = function(event)
      set_branch(event.buf)
      vim.cmd.redrawstatus()
    end,
  })

  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'GitSignsUpdate',
    callback = function()
      refresh_current_buffer()
    end,
  })
end

return M
