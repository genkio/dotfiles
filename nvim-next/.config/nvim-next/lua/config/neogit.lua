local M = {}
local refresh_state = {
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

local function current_is_status()
  return vim.bo.filetype == 'NeogitStatus'
end

local function dispatch_refresh()
  local ok, neogit = pcall(require, 'neogit')
  if not ok or not should_refresh() then
    refresh_state.pending = false
    return
  end

  neogit.dispatch_refresh()
end

local function request_refresh()
  if refresh_state.pending or not should_refresh() or not current_is_status() then
    return
  end

  refresh_state.pending = true
  dispatch_refresh()
end

local function replace_neogit_checktime_autocmd()
  local group = require('neogit').autocmd_group

  for _, autocmd in ipairs(vim.api.nvim_get_autocmds {
    event = 'User',
    group = group,
    pattern = 'NeogitStatusRefreshed',
  }) do
    vim.api.nvim_del_autocmd(autocmd.id)
  end

  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'NeogitStatusRefreshed',
    callback = function()
      require('config.auto_reload').checktime()
    end,
  })
end

function M.setup()
  local neogit = require 'neogit'

  neogit.setup {
    integrations = {
      snacks = true,
      diffview = true,
    },
  }

  replace_neogit_checktime_autocmd()

  local group = vim.api.nvim_create_augroup('nvim-next-neogit-refresh', { clear = true })
  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'NeogitStatusRefreshed',
    callback = function()
      refresh_state.pending = false
    end,
  })

  vim.api.nvim_create_autocmd({ 'CursorHold', 'FocusGained' }, {
    group = group,
    callback = function()
      request_refresh()
    end,
  })

  vim.keymap.set('n', '<leader>gg', function()
    neogit.open { cwd = neogit_cwd() }
  end, { desc = 'Git status' })
end

return M
