local M = {}

function M.resolve_base()
  local dir = vim.fn.getcwd()

  local function git_out(args)
    local cmd = { 'git', '-C', dir }
    vim.list_extend(cmd, args)
    local out = vim.fn.systemlist(cmd)
    if vim.v.shell_error ~= 0 then
      return nil
    end
    return out
  end

  local function git_ok(args)
    local cmd = { 'git', '-C', dir }
    vim.list_extend(cmd, args)
    vim.fn.system(cmd)
    return vim.v.shell_error == 0
  end

  local head = git_out { 'symbolic-ref', '--quiet', '--short', 'refs/remotes/origin/HEAD' }
  if head and head[1] and head[1] ~= '' then
    return head[1]
  end

  for _, name in ipairs { 'origin/main', 'origin/master', 'main', 'master' } do
    if git_ok { 'rev-parse', '--verify', '--quiet', name } then
      return name
    end
  end
end

local function swap_local_to_left()
  local ok, lib = pcall(require, 'diffview.lib')
  if not ok then
    return
  end

  local view = lib.get_current_view()
  local layout = view and view.cur_layout or nil
  if not (layout and layout.a and layout.b) then
    return
  end

  local win_a = layout.a.id
  local win_b = layout.b.id
  if not (vim.api.nvim_win_is_valid(win_a) and vim.api.nvim_win_is_valid(win_b)) then
    return
  end

  local pos_a = vim.api.nvim_win_get_position(win_a)
  local pos_b = vim.api.nvim_win_get_position(win_b)

  local should_swap = false
  if layout.name == 'diff2_horizontal' then
    should_swap = pos_a[2] < pos_b[2]
  elseif layout.name == 'diff2_vertical' then
    should_swap = pos_a[1] < pos_b[1]
  end

  if should_swap then
    vim.api.nvim_win_call(win_a, function()
      vim.cmd 'wincmd x'
    end)
  end
end

function M.open()
  local base = M.resolve_base()
  if not base then
    vim.notify('Could not find default branch to diff against', vim.log.levels.WARN)
    return
  end

  local group = vim.api.nvim_create_augroup('custom-diffview-pr-review', { clear = false })
  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'DiffviewViewOpened',
    once = true,
    callback = swap_local_to_left,
  })

  vim.cmd(('DiffviewOpen %s...HEAD --imply-local'):format(base))
end

return M
