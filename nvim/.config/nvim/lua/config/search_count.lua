local M = {}

local state = {}

local SEARCHCOUNT_TIMEOUT_MS = 100

local function scratch_buf()
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
    state.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.buf].bufhidden = 'hide'
  end

  return state.buf
end

function M.hide()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
end

local function render(text)
  local buf = scratch_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { ' ' .. text .. ' ' })

  local config = {
    relative = 'win',
    win = vim.api.nvim_get_current_win(),
    anchor = 'NE',
    row = 0,
    col = vim.api.nvim_win_get_width(0),
    width = vim.fn.strdisplaywidth(text) + 2,
    height = 1,
    style = 'minimal',
    focusable = false,
    zindex = 200,
  }

  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_config(state.win, config)
    return
  end

  config.noautocmd = true
  state.win = vim.api.nvim_open_win(buf, false, config)
  vim.wo[state.win].winhighlight = 'Normal:Search'
end

local function count_text(pattern)
  local opts = { recompute = 1, maxcount = 0, timeout = SEARCHCOUNT_TIMEOUT_MS }
  if pattern then
    opts.pattern = pattern
  end

  local ok, result = pcall(vim.fn.searchcount, opts)
  if not ok or type(result) ~= 'table' or not result.total then
    return nil
  end

  if result.incomplete == 1 then
    return result.current .. '/?'
  end

  return result.current .. '/' .. result.total
end

local function eligible()
  return vim.fn.win_gettype() == ''
end

local function preview(pattern)
  local text = eligible() and pattern ~= '' and count_text(pattern) or nil
  if text then
    render(text)
  else
    M.hide()
  end

  pcall(vim.cmd.redraw)
end

function M.refresh()
  if vim.api.nvim_get_current_win() == state.win then
    return
  end

  local text = eligible() and vim.v.hlsearch == 1 and count_text(nil) or nil
  if text then
    render(text)
  else
    M.hide()
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup('nvim-next-search-count', { clear = true })

  vim.api.nvim_create_autocmd('CmdlineChanged', {
    group = group,
    pattern = { '/', '?' },
    callback = function()
      preview(vim.fn.getcmdline())
    end,
  })

  vim.api.nvim_create_autocmd('CmdlineLeave', {
    group = group,
    pattern = { '/', '?' },
    callback = function()
      if vim.v.event.abort then
        M.hide()
        return
      end
      vim.schedule(M.refresh)
    end,
  })

  vim.api.nvim_create_autocmd({ 'CursorMoved', 'InsertLeave', 'WinEnter', 'VimResized' }, {
    group = group,
    callback = function()
      M.refresh()
    end,
  })

  vim.api.nvim_create_autocmd({ 'InsertEnter', 'WinLeave' }, {
    group = group,
    callback = function()
      M.hide()
    end,
  })
end

return M
