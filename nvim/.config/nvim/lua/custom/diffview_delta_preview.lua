local M = {}

local state = {
  buf = nil,
  win = nil,
}

local function close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    vim.api.nvim_buf_delete(state.buf, { force = true })
  end
  state.buf = nil
  state.win = nil
end

local function current_file()
  local ok, lib = pcall(require, 'diffview.lib')
  if not ok then
    return nil, 'Diffview is not available'
  end

  local view = lib.get_current_view()
  if not (view and view.infer_cur_file) then
    return nil, 'Not in an active Diffview review'
  end

  local file = view:infer_cur_file(false)
  if not (file and file.path) then
    return nil, 'Place cursor on a file in Diffview'
  end

  local root = view.adapter and view.adapter.ctx and (view.adapter.ctx.toplevel or view.adapter.ctx.dir) or vim.fn.getcwd()
  return {
    path = file.path,
    absolute_path = file.absolute_path or vim.fs.joinpath(root, file.path),
    root = root,
  }
end

function M.open()
  local file, err = current_file()
  if not file then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end

  local base = require('custom.diffview_pr_review').resolve_base()
  if not base then
    vim.notify('Could not find default branch to diff against', vim.log.levels.WARN)
    return
  end

  local raw = vim.system({
    'git',
    '-C',
    file.root,
    'diff',
    '--no-ext-diff',
    base .. '...HEAD',
    '--',
    file.path,
  }, { text = true }):wait()

  if raw.code ~= 0 then
    vim.notify(vim.trim(raw.stderr or 'Failed to build git diff'), vim.log.levels.ERROR)
    return
  end

  if vim.trim(raw.stdout or '') == '' then
    vim.notify('No diff for current file against the review base', vim.log.levels.INFO)
    return
  end

  close()

  local buf = vim.api.nvim_create_buf(false, false)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false

  local width = math.floor(vim.o.columns * 0.92)
  local height = math.floor(vim.o.lines * 0.8)
  local title = string.format(' Delta: %s (%s...HEAD) ', vim.fn.fnamemodify(file.path, ':t'), base)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = 'minimal',
    border = 'rounded',
    title = title,
    title_pos = 'center',
  })

  state.buf = buf
  state.win = win

  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = 'no'
  vim.wo[win].wrap = false

  vim.keymap.set('n', 'q', close, { buffer = buf, desc = 'Delta preview: close' })
  vim.keymap.set('n', '<Esc>', close, { buffer = buf, desc = 'Delta preview: close' })

  local command = string.format(
    'git -C %s diff --color=always %s -- %s | delta --paging=never',
    vim.fn.shellescape(file.root),
    vim.fn.shellescape(base .. '...HEAD'),
    vim.fn.shellescape(file.path)
  )

  vim.api.nvim_buf_call(buf, function()
    vim.fn.termopen({ '/bin/zsh', '-lc', command })
  end)

  vim.defer_fn(function()
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_set_current_win(state.win)
      vim.cmd 'stopinsert'
    end
  end, 30)
end

return M
