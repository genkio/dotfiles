-- custom/inline_send.lua
-- Select code, write a message, send both to an LLM in a sibling tmux pane.

local M = {}

local state = {
  float_buf = nil,
  float_win = nil,
}

local function build_file_reference(path, start_line, end_line)
  return string.format('File: %s:%d-%d', path, start_line, end_line)
end

local function is_neogit_diff_line_component(component)
  return component
    and (
      component.options.line_hl == 'NeogitDiffContext'
      or component.options.line_hl == 'NeogitDiffAdd'
      or component.options.line_hl == 'NeogitDiffDelete'
    )
end

local function neogit_diff_path(path)
  local ok_git, git = pcall(require, 'neogit.lib.git')
  local relative_path = vim.trim(path):match '-> (.+)$' or vim.trim(path)
  if ok_git and git.repo and git.repo.worktree_root then
    return vim.fs.joinpath(git.repo.worktree_root, relative_path)
  end

  return relative_path
end

local function resolve_diffview_path(path)
  if not path:match '^diffview://' then
    return path
  end

  local ok_lib, lib = pcall(require, 'diffview.lib')
  if not ok_lib then
    return path
  end

  local view = lib.get_current_view()
  local entry = view and view.cur_entry or nil
  if entry and entry.absolute_path then
    return entry.absolute_path
  end

  return path
end

local function get_neogit_status_context()
  local ok_status, status = pcall(require, 'neogit.buffers.status')
  local ok_jump, jump = pcall(require, 'neogit.lib.jump')
  if not ok_status or not ok_jump then
    return nil, nil, 'Neogit is not available'
  end

  local status_buffer = status.instance(vim.uv.cwd())
  if not status_buffer or not status_buffer.buffer or not status_buffer.buffer.ui then
    return nil, nil, 'Neogit status buffer is not ready'
  end

  return status_buffer, jump
end

local function find_neogit_hunk(item, line)
  if not item or not item.diff or not item.diff.hunks then
    return nil
  end

  for _, hunk in ipairs(item.diff.hunks) do
    if line > hunk.first and line <= hunk.last then
      return hunk
    end
  end
end

local function resolve_neogit_diff_context()
  if vim.bo.filetype ~= 'NeogitStatus' then
    return nil
  end

  local status_buffer, jump, err = get_neogit_status_context()
  if not status_buffer then
    return nil, err
  end

  local item = status_buffer.buffer.ui:get_item_under_cursor()
  if not item or not item.absolute_path then
    return nil, 'Place cursor on a file in Neogit'
  end

  if not item.diff or not item.diff.hunks then
    return nil, 'Place cursor on an expanded Neogit diff line'
  end

  local cursor_line = status_buffer.buffer:cursor_line()
  local hunk = find_neogit_hunk(item, cursor_line)
  if not hunk then
    return nil, 'Place cursor on a diff content line'
  end

  local offset = cursor_line - hunk.first
  local location = jump.translate_hunk_location(hunk, offset)
  if not location then
    return nil, 'Place cursor on a diff content line'
  end

  local prefix = string.sub(location.line, 1, 1)
  if prefix ~= '+' and prefix ~= '-' and prefix ~= ' ' then
    return nil, 'Place cursor on a diff content line'
  end

  local line_number = jump.adjust_row(hunk.disk_from, offset, hunk.lines, '-')
  return {
    file = item.absolute_path,
    start_line = line_number,
    end_line = line_number,
    diff_line = location.line,
  }
end

local function resolve_neogit_visual_context()
  if vim.bo.filetype ~= 'NeogitStatus' then
    return nil
  end

  local status_buffer, jump, err = get_neogit_status_context()
  if not status_buffer then
    return nil, err
  end

  local first_line = vim.fn.line "'<"
  local last_line = vim.fn.line "'>"
  if first_line == 0 or last_line == 0 then
    return nil, 'No visual selection found'
  end

  local item = nil
  for _, section in ipairs(status_buffer.buffer.ui.item_index or {}) do
    for _, candidate in pairs(section.items or {}) do
      if candidate.first and candidate.last and candidate.first <= first_line and candidate.last >= last_line then
        item = candidate
        break
      end
    end
    if item then
      break
    end
  end

  if not item or not item.absolute_path then
    return nil, 'Select lines within a single file in Neogit'
  end

  local first_hunk = find_neogit_hunk(item, first_line)
  local last_hunk = find_neogit_hunk(item, last_line)
  if not first_hunk or not last_hunk or first_hunk ~= last_hunk then
    return nil, 'Select diff content lines within a single Neogit hunk'
  end

  local start_offset = first_line - first_hunk.first
  local end_offset = last_line - first_hunk.first
  local start_location = jump.translate_hunk_location(first_hunk, start_offset)
  local end_location = jump.translate_hunk_location(first_hunk, end_offset)
  if not start_location or not end_location then
    return nil, 'Select diff content lines within a single Neogit hunk'
  end

  return {
    file = item.absolute_path,
    start_line = jump.adjust_row(first_hunk.disk_from, start_offset, first_hunk.lines, '-'),
    end_line = jump.adjust_row(first_hunk.disk_from, end_offset, first_hunk.lines, '-'),
  }
end

local function get_neogit_commit_view_context()
  local ok_commit_view, commit_view = pcall(require, 'neogit.buffers.commit_view')
  local ok_jump, jump = pcall(require, 'neogit.lib.jump')
  if not ok_commit_view or not ok_jump then
    return nil, nil, 'Neogit commit view is not available'
  end

  local view = commit_view.instance
  if not view or not view.buffer or not view.buffer.ui then
    return nil, nil, 'Neogit commit view is not ready'
  end

  return view, jump
end

local function resolve_neogit_commit_diff_context()
  if vim.bo.filetype ~= 'NeogitCommitView' then
    return nil
  end

  local view, jump, err = get_neogit_commit_view_context()
  if not view then
    return nil, err
  end

  local component = view.buffer.ui:get_component_under_cursor(is_neogit_diff_line_component)
  if not component then
    return nil, 'Place cursor on a diff content line in Neogit commit view'
  end

  local hunk_component = component.parent and component.parent.parent
  local hunk = hunk_component and hunk_component.options.hunk
  if not hunk or not hunk.file then
    return nil, 'Unable to resolve file path in Neogit commit view'
  end

  local offset = view.buffer:cursor_line() - hunk_component.position.row_start
  local location = jump.translate_hunk_location(hunk, offset)
  if not location then
    return nil, 'Place cursor on a diff content line in Neogit commit view'
  end

  local prefix = string.sub(location.line, 1, 1)
  if prefix ~= '+' and prefix ~= '-' and prefix ~= ' ' then
    return nil, 'Place cursor on a diff content line in Neogit commit view'
  end

  local line_number = prefix == '-' and location.old or location.new
  return {
    file = neogit_diff_path(hunk.file),
    start_line = line_number,
    end_line = line_number,
    diff_line = location.line,
  }
end

local function resolve_neogit_commit_visual_context()
  if vim.bo.filetype ~= 'NeogitCommitView' then
    return nil
  end

  local view, jump, err = get_neogit_commit_view_context()
  if not view then
    return nil, err
  end

  local first_line = vim.fn.line "'<"
  local last_line = vim.fn.line "'>"
  if first_line == 0 or last_line == 0 then
    return nil, 'No visual selection found'
  end

  local first_component = view.buffer.ui:get_component_on_line(first_line, is_neogit_diff_line_component)
  local last_component = view.buffer.ui:get_component_on_line(last_line, is_neogit_diff_line_component)
  if not first_component or not last_component then
    return nil, 'Select diff content lines in Neogit commit view'
  end

  local first_hunk_component = first_component.parent and first_component.parent.parent
  local last_hunk_component = last_component.parent and last_component.parent.parent
  if not first_hunk_component or first_hunk_component ~= last_hunk_component then
    return nil, 'Select diff content lines within a single Neogit commit hunk'
  end

  local hunk = first_hunk_component.options.hunk
  if not hunk or not hunk.file then
    return nil, 'Unable to resolve file path in Neogit commit view'
  end

  local start_offset = first_line - first_hunk_component.position.row_start
  local end_offset = last_line - first_hunk_component.position.row_start
  local start_location = jump.translate_hunk_location(hunk, start_offset)
  local end_location = jump.translate_hunk_location(hunk, end_offset)
  if not start_location or not end_location then
    return nil, 'Select diff content lines within a single Neogit commit hunk'
  end

  return {
    file = neogit_diff_path(hunk.file),
    start_line = string.sub(start_location.line, 1, 1) == '-' and start_location.old or start_location.new,
    end_line = string.sub(end_location.line, 1, 1) == '-' and end_location.old or end_location.new,
  }
end

local function resolve_context(from_visual)
  local buf = vim.api.nvim_get_current_buf()
  local file = vim.api.nvim_buf_get_name(buf)
  local filetype = vim.bo[buf].filetype

  if from_visual then
    if filetype == 'NeogitCommitView' then
      local neogit_context, err = resolve_neogit_commit_visual_context()
      if neogit_context then
        return neogit_context
      end

      return nil, err or 'Unable to resolve Neogit commit selection'
    end

    if filetype == 'NeogitStatus' then
      local neogit_context, err = resolve_neogit_visual_context()
      if neogit_context then
        return neogit_context
      end

      return nil, err or 'Unable to resolve Neogit selection'
    end

    if file == '' then
      return nil, 'Buffer has no file path'
    end

    local start_line = vim.fn.line "'<"
    local end_line = vim.fn.line "'>"

    return {
      file = resolve_diffview_path(vim.fn.fnamemodify(file, ':p')),
      start_line = start_line,
      end_line = end_line,
    }
  end

  if filetype == 'NeogitCommitView' then
    local neogit_context, err = resolve_neogit_commit_diff_context()
    if neogit_context then
      return neogit_context
    end

    return nil, err or 'Unable to resolve Neogit commit diff context'
  end

  if filetype == 'NeogitStatus' then
    local neogit_context, err = resolve_neogit_diff_context()
    if neogit_context then
      return neogit_context
    end

    return nil, err or 'Unable to resolve Neogit diff context'
  end

  if file == '' then
    local neogit_context, err = resolve_neogit_diff_context()
    if neogit_context then
      return neogit_context
    end

    return nil, err or 'Buffer has no file path'
  end

  return {
    file = resolve_diffview_path(vim.fn.fnamemodify(file, ':p')),
  }
end

--- List other tmux panes in the current window.
--- Returns list of { id, index, title, cmd } or nil + error message.
local function list_other_panes()
  local current = os.getenv 'TMUX_PANE'
  if not current then
    return nil, 'Not running inside tmux'
  end

  local fmt = '#{pane_id}\t#{pane_index}\t#{pane_title}\t#{pane_current_command}'
  local result = vim.system({ 'tmux', 'list-panes', '-F', fmt }, { text = true }):wait()
  if result.code ~= 0 then
    return nil, 'Failed to list tmux panes'
  end

  local panes = {}
  for line in result.stdout:gmatch '[^\r\n]+' do
    local id, index, title, cmd = line:match '([^\t]+)\t([^\t]+)\t([^\t]*)\t([^\t]*)'
    if id and id ~= current then
      table.insert(panes, { id = id, index = index, title = title, cmd = cmd })
    end
  end

  if #panes == 0 then
    return nil, 'No other panes found'
  end

  return panes
end

--- Pick a target pane: auto-select if only one other pane, otherwise show a picker.
--- Calls callback(pane_id) on selection.
local function pick_pane(callback)
  local panes, err = list_other_panes()
  if not panes then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end

  if #panes == 1 then
    callback(panes[1].id)
    return
  end

  vim.ui.select(panes, {
    prompt = 'Send to pane:',
    format_item = function(pane)
      return string.format('[%s] %s (%s)', pane.index, pane.cmd, pane.id)
    end,
  }, function(choice)
    if choice then
      callback(choice.id)
    end
  end)
end

--- Send text to the sibling tmux pane.
local function send_to_pane(pane_id, text)
  local result = vim.system({ 'tmux', 'set-buffer', '--', text }):wait()
  if result.code ~= 0 then
    vim.notify('Failed to set tmux buffer', vim.log.levels.ERROR)
    return false
  end

  result = vim.system({ 'tmux', 'paste-buffer', '-t', pane_id }):wait()
  if result.code ~= 0 then
    vim.notify('Failed to paste to pane', vim.log.levels.ERROR)
    return false
  end

  result = vim.system({ 'tmux', 'send-keys', '-t', pane_id, 'Enter' }):wait()
  if result.code ~= 0 then
    vim.notify('Failed to send Enter', vim.log.levels.ERROR)
    return false
  end

  return true
end

--- Close the floating window.
local function close_float()
  if state.float_win and vim.api.nvim_win_is_valid(state.float_win) then
    vim.api.nvim_win_close(state.float_win, true)
  end
  if state.float_buf and vim.api.nvim_buf_is_valid(state.float_buf) then
    vim.api.nvim_buf_delete(state.float_buf, { force = true })
  end
  state.float_win = nil
  state.float_buf = nil
end

--- Send the full float buffer content to the tmux pane.
local function send_message()
  if not state.float_buf or not vim.api.nvim_buf_is_valid(state.float_buf) then
    vim.notify('No message buffer open', vim.log.levels.ERROR)
    return
  end

  local lines = vim.api.nvim_buf_get_lines(state.float_buf, 0, -1, false)

  while #lines > 0 and vim.trim(lines[1]) == '' do
    table.remove(lines, 1)
  end
  while #lines > 0 and vim.trim(lines[#lines]) == '' do
    table.remove(lines)
  end

  if #lines == 0 then
    vim.notify('Message is empty', vim.log.levels.WARN)
    return
  end

  local payload = table.concat(lines, '\n')
  vim.fn.setreg('+', payload)

  pick_pane(function(pane_id)
    close_float()
    if send_to_pane(pane_id, payload) then
      vim.notify(string.format('Sent to pane %s', pane_id), vim.log.levels.INFO)
    end
  end)
end

--- Open float to compose a message. Visual mode includes the selection as a file reference.
--- In Neogit status diffs, normal mode can also capture the diff line under the cursor.
function M.open_editor(from_visual)
  local context, err = resolve_context(from_visual)
  if not context then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end

  local file = context.file

  close_float()

  local float_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[float_buf].buftype = 'nofile'
  vim.bo[float_buf].filetype = 'markdown'

  -- Pre-populate with a file reference when line context is available
  local content = {}
  local start_line = context.start_line
  local end_line = context.end_line
  if start_line and start_line > 0 and end_line and end_line > 0 then
    table.insert(content, build_file_reference(file, start_line, end_line))
    if context.diff_line then
      table.insert(content, string.format('Diff: %s', context.diff_line))
    end
    table.insert(content, '')
  end
  if #content > 0 then
    vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, content)
  end

  local width = math.floor(vim.o.columns * 0.6)
  local height = math.max(math.floor(vim.o.lines * 0.3), 5)
  local short_name = vim.fn.fnamemodify(file, ':t')
  local title
  if start_line and start_line > 0 then
    title = string.format(' Inline: %s:%d-%d ', short_name, start_line, end_line)
  else
    title = ' Inline '
  end

  local float_win = vim.api.nvim_open_win(float_buf, true, {
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

  state.float_buf = float_buf
  state.float_win = float_win

  local line_count = vim.api.nvim_buf_line_count(float_buf)
  vim.api.nvim_win_set_cursor(float_win, { line_count, 0 })

  vim.keymap.set('n', '<leader>is', send_message, { buffer = float_buf, desc = 'Inline: Send message' })
  vim.keymap.set('n', 'q', close_float, { buffer = float_buf, desc = 'Inline: Cancel' })
  vim.keymap.set('n', '<Esc>', close_float, { buffer = float_buf, desc = 'Inline: Cancel' })

  vim.cmd 'startinsert!'
end

function M.setup()
  vim.keymap.set('n', '<leader>ie', function()
    M.open_editor(false)
  end, { desc = 'Inline: Open message editor' })

  vim.keymap.set('v', '<leader>ie', function()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'nx', false)
    vim.schedule(function()
      M.open_editor(true)
    end)
  end, { desc = 'Inline: Select code and open editor' })
end

return M
