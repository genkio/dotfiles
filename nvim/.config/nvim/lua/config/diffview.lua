-- Lazy-loaded Diffview integration and review commands.
--
-- Diffview is kept out of startup until one of the git review commands is used.
-- This module installs forwarding commands, resolves a sensible default branch,
-- opens branch and worktree reviews, and nudges two-way diffs so the local side
-- appears on the left for the layouts used in this setup.

local M = {}
local loaded = false

function M.ensure_loaded()
  if loaded then
    return
  end

  for _, name in ipairs { 'DiffviewOpen', 'DiffviewClose', 'DiffviewToggleFiles', 'DiffviewFocusFiles', 'DiffviewFileHistory' } do
    pcall(vim.api.nvim_del_user_command, name)
  end
  vim.cmd.packadd { 'plenary.nvim', magic = { file = false } }
  vim.cmd.packadd { 'diffview.nvim', magic = { file = false } }

  require('diffview').setup {
    use_icons = false,
  }

  loaded = true
end

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
  M.ensure_loaded()

  local base = resolve_base()
  if not base then
    vim.notify('Could not find default branch to diff against', vim.log.levels.WARN)
    return
  end

  swap_on_open 'nvim-next-diffview-review'
  vim.cmd(('DiffviewOpen %s...HEAD --imply-local'):format(base))
end

local function open_worktree()
  M.ensure_loaded()
  swap_on_open 'nvim-next-diffview-worktree'
  vim.cmd 'DiffviewOpen'
end

local function file_history_current()
  M.ensure_loaded()
  vim.cmd 'DiffviewFileHistory %'
end

local function file_history_repo()
  M.ensure_loaded()
  vim.cmd 'DiffviewFileHistory'
end

local function close_diffview()
  if loaded then
    vim.cmd 'DiffviewClose'
  end
end

local function forward_command(name)
  return function(opts)
    M.ensure_loaded()
    local diffview = require 'diffview'

    if name == 'DiffviewOpen' then
      diffview.open(require('diffview.arg_parser').scan(opts.args).args)
      return
    end

    if name == 'DiffviewFileHistory' then
      local range = nil
      if opts.range > 0 then
        range = { opts.line1, opts.line2 }
      end
      diffview.file_history(range, require('diffview.arg_parser').scan(opts.args).args)
      return
    end

    if name == 'DiffviewClose' then
      diffview.close()
      return
    end

    if name == 'DiffviewFocusFiles' then
      diffview.emit 'focus_files'
      return
    end

    if name == 'DiffviewToggleFiles' then
      diffview.emit 'toggle_files'
    end
  end
end

function M.setup()
  vim.api.nvim_create_user_command('DiffviewOpen', forward_command 'DiffviewOpen', {
    nargs = '*',
    bang = true,
  })
  vim.api.nvim_create_user_command('DiffviewClose', forward_command 'DiffviewClose', {
    nargs = '*',
    bang = true,
  })
  vim.api.nvim_create_user_command('DiffviewToggleFiles', forward_command 'DiffviewToggleFiles', {
    nargs = '*',
    bang = true,
  })
  vim.api.nvim_create_user_command('DiffviewFocusFiles', forward_command 'DiffviewFocusFiles', {
    nargs = '*',
    bang = true,
  })
  vim.api.nvim_create_user_command('DiffviewFileHistory', forward_command 'DiffviewFileHistory', {
    nargs = '*',
    bang = true,
  })

  vim.keymap.set('n', '<leader>gd', open_review, { desc = 'Git diff vs default branch' })
  vim.keymap.set('n', '<leader>gw', open_worktree, { desc = 'Git working tree vs index diff' })
  vim.keymap.set('n', '<leader>gD', close_diffview, { desc = 'Git diff view close' })
  vim.keymap.set('n', '<leader>gf', file_history_current, { desc = 'Git file history' })
  vim.keymap.set('n', '<leader>gF', file_history_repo, { desc = 'Git repo file history' })
end

return M
