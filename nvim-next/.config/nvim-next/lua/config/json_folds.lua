local M = {}

local namespace = vim.api.nvim_create_namespace('config.json_folds')
local state_key = 'json_fold_state'

local OPEN_TO_CLOSE = {
  ['{'] = '}',
  ['['] = ']',
}

local function current_window_state()
  local state = vim.w[state_key]
  if type(state) ~= 'table' then
    state = {}
    vim.w[state_key] = state
  end
  return state
end

local function save_window_state(state)
  vim.w[state_key] = state
end

local function set_cursor(line)
  vim.api.nvim_win_set_cursor(0, { line, 0 })
end

local function range_length(range)
  return range.finish - range.start
end

local function get_range_for_id(bufnr, id)
  local mark = vim.api.nvim_buf_get_extmark_by_id(bufnr, namespace, id, { details = true })
  if #mark == 0 then
    return nil
  end

  local details = mark[3]
  if not details or details.end_row == nil then
    return nil
  end

  return {
    start = mark[1] + 1,
    finish = details.end_row + 1,
  }
end

local function sort_ids_by_range(ids, bufnr, descending)
  table.sort(ids, function(left, right)
    local left_range = get_range_for_id(bufnr, left)
    local right_range = get_range_for_id(bufnr, right)

    if not left_range then
      return false
    end
    if not right_range then
      return true
    end

    local left_length = range_length(left_range)
    local right_length = range_length(right_range)

    if left_length == right_length then
      if descending then
        return left_range.start > right_range.start
      end
      return left_range.start < right_range.start
    end

    if descending then
      return left_length > right_length
    end
    return left_length < right_length
  end)
end

local function rebuild_window_folds()
  local bufnr = vim.api.nvim_get_current_buf()
  local state = current_window_state()
  local ids = {}

  for id in pairs(state) do
    if get_range_for_id(bufnr, id) then
      ids[#ids + 1] = id
    else
      state[id] = nil
    end
  end

  save_window_state(state)

  local view = vim.fn.winsaveview()

  vim.opt_local.foldmethod = 'manual'
  vim.opt_local.foldlevel = 99
  vim.opt_local.foldenable = true
  vim.cmd 'silent! zE'

  sort_ids_by_range(ids, bufnr, false)

  for _, id in ipairs(ids) do
    local range = get_range_for_id(bufnr, id)
    if range and range.start < range.finish then
      vim.cmd(('%d,%dfold'):format(range.start, range.finish))
      if state[id] then
        set_cursor(range.start)
        vim.cmd 'silent! normal! zc'
      end
    end
  end

  sort_ids_by_range(ids, bufnr, true)

  for _, id in ipairs(ids) do
    if not state[id] then
      local range = get_range_for_id(bufnr, id)
      if range then
        set_cursor(range.start)
        vim.cmd 'silent! normal! zo'
      end
    end
  end

  vim.fn.winrestview(view)
end

local function line_comment_prefix(filetype)
  if filetype == 'jsonc' then
    return '//'
  end
  return nil
end

local function find_opener_on_line(line, start_col, filetype)
  local in_string = false
  local escaped = false
  local in_block_comment = false
  local line_comment = line_comment_prefix(filetype)

  for col = 1, #line do
    local ch = line:sub(col, col)
    local next_ch = line:sub(col + 1, col + 1)

    if in_string then
      if escaped then
        escaped = false
      elseif ch == '\\' then
        escaped = true
      elseif ch == '"' then
        in_string = false
      end
    elseif in_block_comment then
      if ch == '*' and next_ch == '/' then
        in_block_comment = false
      end
    else
      if line_comment and ch == '/' and next_ch == '/' then
        break
      end
      if filetype == 'jsonc' and ch == '/' and next_ch == '*' then
        in_block_comment = true
      elseif ch == '"' then
        in_string = true
      elseif (ch == '{' or ch == '[') and col >= start_col then
        return ch, col
      end
    end
  end

  return nil
end

local function find_block_range_at_cursor()
  local bufnr = vim.api.nvim_get_current_buf()
  local filetype = vim.bo[bufnr].filetype
  local cursor = vim.api.nvim_win_get_cursor(0)
  local start_line = cursor[1]
  local start_col = cursor[2] + 1
  local line = vim.api.nvim_get_current_line()
  local opener, opener_col = find_opener_on_line(line, start_col, filetype)

  if not opener then
    opener, opener_col = find_opener_on_line(line, 1, filetype)
    if not opener then
      return nil
    end
  end

  local closer = OPEN_TO_CLOSE[opener]
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, -1, false)
  local in_string = false
  local escaped = false
  local in_block_comment = false
  local line_comment = line_comment_prefix(filetype)
  local depth = 0

  for index, current_line in ipairs(lines) do
    local line_number = start_line + index - 1
    local col = line_number == start_line and opener_col or 1

    while col <= #current_line do
      local ch = current_line:sub(col, col)
      local next_ch = current_line:sub(col + 1, col + 1)

      if in_string then
        if escaped then
          escaped = false
        elseif ch == '\\' then
          escaped = true
        elseif ch == '"' then
          in_string = false
        end
      elseif in_block_comment then
        if ch == '*' and next_ch == '/' then
          in_block_comment = false
          col = col + 1
        end
      else
        if line_comment and ch == '/' and next_ch == '/' then
          break
        end
        if filetype == 'jsonc' and ch == '/' and next_ch == '*' then
          in_block_comment = true
          col = col + 1
        elseif ch == '"' then
          in_string = true
        elseif ch == opener then
          depth = depth + 1
        elseif ch == closer then
          depth = depth - 1
          if depth == 0 then
            return {
              start = start_line,
              finish = line_number,
            }
          end
        end
      end

      col = col + 1
    end
  end

  return nil
end

local function find_state_id_for_range(range)
  local bufnr = vim.api.nvim_get_current_buf()

  for id in pairs(current_window_state()) do
    local current = get_range_for_id(bufnr, id)
    if current and current.start == range.start and current.finish == range.finish then
      return id
    end
  end

  return nil
end

local function ensure_state_id(range)
  local bufnr = vim.api.nvim_get_current_buf()
  local existing = find_state_id_for_range(range)
  if existing then
    return existing
  end

  local finish_line = vim.api.nvim_buf_get_lines(bufnr, range.finish - 1, range.finish, false)[1] or ''

  return vim.api.nvim_buf_set_extmark(bufnr, namespace, range.start - 1, 0, {
    end_row = range.finish - 1,
    end_col = #finish_line,
    right_gravity = false,
    end_right_gravity = true,
  })
end

local function update_range_state(range, closed)
  local state = current_window_state()
  local id = ensure_state_id(range)

  state[id] = closed

  save_window_state(state)

  rebuild_window_folds()
end

local function fallback(keys)
  vim.cmd(('silent! normal! %s'):format(keys))
end

local function act_on_current_range(closed, fallback_keys)
  local range = find_block_range_at_cursor()
  if not range then
    fallback(fallback_keys)
    return
  end

  update_range_state(range, closed)
end

function M.close_current()
  act_on_current_range(true, 'zc')
end

function M.open_current()
  act_on_current_range(false, 'zo')
end

function M.setup_buffer()
  vim.opt_local.foldmethod = 'manual'
  vim.opt_local.foldlevel = 99
  current_window_state()

  if vim.b.json_folds_setup then
    return
  end

  vim.b.json_folds_setup = true

  vim.keymap.set('n', 'zc', function()
    M.close_current()
  end, { buffer = true, desc = 'Close JSON block under cursor' })

  vim.keymap.set('n', 'zo', function()
    M.open_current()
  end, { buffer = true, desc = 'Open JSON block under cursor' })
end

return M
