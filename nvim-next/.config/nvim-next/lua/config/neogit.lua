local M = {}
local refresh_state = {
  timer = nil,
  pending = false,
}

local function neogit_cwd()
  local name = vim.api.nvim_buf_get_name(0)
  if name ~= '' then
    local dir = vim.fs.dirname(vim.fs.normalize(name))
    if dir and vim.fn.isdirectory(dir) == 1 then
      return dir
    end
  end

  return vim.uv.cwd() or vim.fn.getcwd()
end

local function should_refresh()
  local ok, status = pcall(require, 'neogit.buffers.status')
  return ok and status.is_open()
end

local function dispatch_refresh()
  local ok, neogit = pcall(require, 'neogit')
  if not ok or not should_refresh() then
    refresh_state.pending = false
    return
  end

  neogit.dispatch_refresh()
end

local function ensure_refresh_timer()
  if refresh_state.timer then
    return
  end

  local timer = assert(vim.uv.new_timer())
  timer:start(1000, 1000, vim.schedule_wrap(function()
    if refresh_state.pending or not should_refresh() then
      return
    end

    refresh_state.pending = true
    dispatch_refresh()
  end))

  refresh_state.timer = timer
end

function M.setup()
  local neogit = require 'neogit'

  neogit.setup {
    integrations = {
      snacks = true,
      diffview = true,
    },
  }

  ensure_refresh_timer()

  local group = vim.api.nvim_create_augroup('nvim-next-neogit-refresh', { clear = true })
  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'NeogitStatusRefreshed',
    callback = function()
      refresh_state.pending = false
    end,
  })

  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = group,
    callback = function()
      if refresh_state.timer then
        refresh_state.timer:stop()
        refresh_state.timer:close()
        refresh_state.timer = nil
      end
    end,
  })

  vim.keymap.set('n', '<leader>gg', function()
    neogit.open { cwd = neogit_cwd() }
  end, { desc = 'Git status' })
end

return M
