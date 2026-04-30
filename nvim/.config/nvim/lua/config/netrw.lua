-- Custom netrw ergonomics for this config's built-in file explorer.
--
-- The module keeps netrw as the explorer while adding a few workflow helpers:
-- reveal the current file when returning to the explorer, make preview windows
-- close predictably when opening files, and auto-update an existing preview as
-- the cursor moves through the tree.

local M = {}
local preview_state = {
  timer = nil,
  target = nil,
  running = false,
}

local function normalize(path)
  return vim.fs.normalize(vim.fn.fnamemodify(path, ':p'))
end

local function current_cwd()
  return normalize(vim.uv.cwd() or vim.fn.getcwd())
end

local function current_file()
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].buftype ~= '' then
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

local function is_descendant(root, path)
  return path == root or vim.startswith(path, root .. '/')
end

local function find_line_with_suffix(suffix, start_line)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for lnum = start_line or 1, #lines do
    if lines[lnum]:sub(-#suffix) == suffix then
      return lnum
    end
  end

  return nil
end

local function focus_line(lnum)
  if not lnum then
    return
  end

  vim.api.nvim_win_set_cursor(0, { lnum, 0 })
end

local function reveal_file_in_explorer(root, path)
  vim.cmd('silent Explore ' .. vim.fn.fnameescape(root))

  if vim.bo.filetype ~= 'netrw' then
    return
  end

  local dir = vim.fs.dirname(path)
  if is_descendant(root, dir) and dir ~= root then
    local browse = vim.fn['netrw#LocalBrowseCheck']
    local relative = dir:sub(#root + 2)
    local cursor_line = 1

    for segment in relative:gmatch '[^/]+' do
      root = vim.fs.joinpath(root, segment)
      browse(root)

      local line = find_line_with_suffix(segment .. '/', cursor_line)
      if not line then
        break
      end

      cursor_line = line
      focus_line(line)
    end
  end

  local file_line = find_line_with_suffix(vim.fs.basename(path), vim.api.nvim_win_get_cursor(0)[1])
  focus_line(file_line)
end

local function preview_window_exists()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_get_option_value('previewwindow', { win = win }) then
      return true
    end
  end

  return false
end

local function cancel_preview_timer()
  if preview_state.timer then
    preview_state.timer:stop()
    preview_state.timer:close()
    preview_state.timer = nil
  end
end

local function should_auto_preview()
  if vim.bo.filetype ~= 'netrw' or not preview_window_exists() then
    preview_state.target = nil
    return false
  end

  local line = vim.trim(vim.api.nvim_get_current_line())
  if line == '' or line:sub(-1) == '/' then
    preview_state.target = nil
    return false
  end

  return true
end

local function trigger_preview()
  if preview_state.running or not should_auto_preview() then
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local target = string.format('%d:%d', bufnr, line)

  if preview_state.target == target then
    return
  end

  preview_state.target = target
  preview_state.running = true

  local keys = vim.api.nvim_replace_termcodes('p', true, false, true)
  vim.api.nvim_feedkeys(keys, 'm', false)

  vim.schedule(function()
    preview_state.running = false
  end)
end

local function schedule_preview()
  cancel_preview_timer()

  if not should_auto_preview() then
    return
  end

  local timer = assert(vim.uv.new_timer())
  timer:start(80, 0, vim.schedule_wrap(function()
    cancel_preview_timer()
    trigger_preview()
  end))
  preview_state.timer = timer
end

local function open_from_netrw()
  local had_preview = preview_window_exists()
  vim.w.nvim_next_from_netrw = true
  local keys = vim.api.nvim_replace_termcodes('<Plug>NetrwLocalBrowseCheck', true, false, true)
  vim.api.nvim_feedkeys(keys, 'm', false)

  if not had_preview then
    return
  end

  vim.schedule(function()
    if vim.bo.filetype ~= 'netrw' and preview_window_exists() then
      pcall(vim.cmd, 'pclose')
    end
  end)
end

local function return_to_explorer()
  if vim.bo.filetype == 'netrw' then
    vim.cmd.Rexplore()
    return
  end

  local file = current_file()
  if vim.w.nvim_next_from_netrw then
    vim.cmd.Rexplore()
    return
  end

  if not file then
    vim.cmd.Rexplore()
    return
  end

  local root = current_cwd()
  if not is_descendant(root, file) then
    root = vim.fs.dirname(file)
  end

  reveal_file_in_explorer(root, file)
end

function M.setup()
  vim.g.netrw_liststyle = 3

  local group = vim.api.nvim_create_augroup('nvim-next-netrw', { clear = true })

  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = 'netrw',
    callback = function(event)
      vim.keymap.set('n', '<CR>', open_from_netrw, {
        buffer = event.buf,
        silent = true,
        desc = 'Open from explorer',
      })

      vim.api.nvim_create_autocmd('CursorMoved', {
        group = group,
        buffer = event.buf,
        callback = schedule_preview,
      })

      vim.api.nvim_create_autocmd({ 'BufLeave', 'InsertEnter' }, {
        group = group,
        buffer = event.buf,
        callback = function()
          preview_state.target = nil
          cancel_preview_timer()
        end,
      })
    end,
  })

  vim.api.nvim_create_autocmd('BufWinEnter', {
    group = group,
    callback = function()
      if vim.wo.previewwindow then
        vim.keymap.set('n', 'q', '<cmd>pclose<CR>', {
          buffer = 0,
          silent = true,
          desc = 'Close preview window',
        })
      end
    end,
  })

  vim.keymap.set('n', '<leader>er', return_to_explorer, {
    desc = 'Return to explorer',
  })
end

return M
