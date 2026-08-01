-- Search match counter.
--
-- Neovim already appends `[3/17]` to the search prompt, but `cmdheight = 0`
-- throws that message away before it can be read. Render the same count in a
-- tiny float at the top right of the current window instead: live while typing
-- `/pattern`, then kept in sync as `n`/`N` walk the matches, and gone as soon as
-- `:nohlsearch` (or `<Esc>`) drops the highlight.

local M = {}

local state = {}

-- Unlimited count would scan the whole buffer on every cursor move, so cap the
-- work by time and report `?` when the scan does not finish.
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

  -- `noautocmd` is rejected by nvim_win_set_config, so it only goes on the open.
  config.noautocmd = true
  state.win = vim.api.nvim_open_win(buf, false, config)
  -- Borrow `Search` rather than a custom group: `:colorscheme` wipes custom
  -- groups, and colors.lua re-picks the scheme when the theme flips.
  vim.wo[state.win].winhighlight = 'Normal:Search'
end

local function count_text(pattern)
  local opts = { recompute = 1, maxcount = 0, timeout = SEARCHCOUNT_TIMEOUT_MS }
  if pattern then
    opts.pattern = pattern
  end

  -- A half-typed pattern (`foo\(`) is invalid and throws.
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
  -- '' is a plain window; skip pickers, cmdwin, quickfix, preview.
  return vim.fn.win_gettype() == ''
end

-- Count for the pattern still being typed at the `/` or `?` prompt.
local function preview(pattern)
  local text = eligible() and pattern ~= '' and count_text(pattern) or nil
  if text then
    render(text)
  else
    M.hide()
  end

  -- Cmdline mode won't necessarily redraw on its own, e.g. once the pattern
  -- stops matching, which would leave the float stale on screen.
  pcall(vim.cmd.redraw)
end

-- Count for the active search register, i.e. after `<CR>`, `n`, `N`, `*`.
function M.refresh()
  -- Never anchor the float to itself.
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
      -- `v:hlsearch` and the cursor only settle after the search runs.
      vim.schedule(M.refresh)
    end,
  })

  -- The float is window-anchored, so scrolling needs no update; only a resize
  -- moves the right edge it hangs from.
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
