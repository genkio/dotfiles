-- custom/inline_send.lua
-- Select code, write a message, send both to an LLM in a sibling tmux pane.

local M = {}

local state = {
  float_buf = nil,
  float_win = nil,
}

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
  local result = vim.system({ 'tmux', 'load-buffer', '-' }, { stdin = text }):wait()
  if result.code ~= 0 then
    vim.notify('Failed to load tmux buffer', vim.log.levels.ERROR)
    return false
  end

  result = vim.system({ 'tmux', 'paste-buffer', '-t', pane_id, '-d' }):wait()
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

  pick_pane(function(pane_id)
    close_float()
    if send_to_pane(pane_id, payload) then
      vim.notify(string.format('Sent to pane %s', pane_id), vim.log.levels.INFO)
    end
  end)
end

--- Open float to compose a message. When from_visual is true, includes the selection as a file reference.
function M.open_editor(from_visual)
  local buf = vim.api.nvim_get_current_buf()
  local file = vim.api.nvim_buf_get_name(buf)
  if file == '' then
    vim.notify('Buffer has no file path', vim.log.levels.ERROR)
    return
  end

  close_float()

  local float_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[float_buf].buftype = 'nofile'
  vim.bo[float_buf].filetype = 'markdown'

  local start_line, end_line
  if from_visual then
    start_line = vim.fn.line "'<"
    end_line = vim.fn.line "'>"
  end

  -- Pre-populate with file reference if called from visual mode
  local content = {}
  if start_line and start_line > 0 and end_line and end_line > 0 then
    local abs_path = vim.fn.fnamemodify(file, ':p')
    table.insert(content, string.format('File: %s:%d-%d', abs_path, start_line, end_line))
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
