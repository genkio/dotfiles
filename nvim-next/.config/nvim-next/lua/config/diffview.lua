local M = {}

local function git_output(args)
  local cmd = { 'git', '-C', vim.fn.getcwd() }
  vim.list_extend(cmd, args)

  local result = vim.system(cmd, { text = true }):wait()
  if result.code ~= 0 then
    return nil
  end

  local output = vim.trim(result.stdout or '')
  if output == '' then
    return nil
  end

  return output
end

local function git_ok(args)
  local cmd = { 'git', '-C', vim.fn.getcwd() }
  vim.list_extend(cmd, args)

  return vim.system(cmd, { text = true }):wait().code == 0
end

local function resolve_base()
  local head = git_output { 'symbolic-ref', '--quiet', '--short', 'refs/remotes/origin/HEAD' }
  if head then
    return head
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

local function swap_on_open(group_name)
  local group = vim.api.nvim_create_augroup(group_name, { clear = false })
  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'DiffviewViewOpened',
    once = true,
    callback = swap_local_to_left,
  })
end

local function open_review()
  local base = resolve_base()
  if not base then
    vim.notify('Could not find default branch to diff against', vim.log.levels.WARN)
    return
  end

  swap_on_open 'nvim-next-diffview-review'
  vim.cmd(('DiffviewOpen %s...HEAD --imply-local'):format(base))
end

local function open_worktree()
  swap_on_open 'nvim-next-diffview-worktree'
  vim.cmd 'DiffviewOpen'
end

local function file_history_current()
  vim.cmd 'DiffviewFileHistory %'
end

local function file_history_repo()
  vim.cmd 'DiffviewFileHistory'
end

function M.setup()
  require('diffview').setup {
    use_icons = false,
  }

  vim.keymap.set('n', '<leader>gd', open_review, { desc = 'Git diff vs default branch' })
  vim.keymap.set('n', '<leader>gw', open_worktree, { desc = 'Git working tree vs index diff' })
  vim.keymap.set('n', '<leader>gD', '<cmd>DiffviewClose<CR>', { desc = 'Git diff view close' })
  vim.keymap.set('n', '<leader>gf', file_history_current, { desc = 'Git file history' })
  vim.keymap.set('n', '<leader>gF', file_history_repo, { desc = 'Git repo file history' })
end

return M
