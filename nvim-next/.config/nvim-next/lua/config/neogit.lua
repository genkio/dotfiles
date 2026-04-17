local M = {}
local loaded = false

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

function M.ensure_loaded()
  if loaded then
    return
  end

  require('config.diffview').ensure_loaded()
  pcall(vim.api.nvim_del_user_command, 'Neogit')
  vim.cmd.packadd { 'neogit', magic = { file = false } }

  local neogit = require 'neogit'

  neogit.setup {
    auto_refresh = true,
    filewatcher = {
      enabled = false,
    },
    integrations = {
      snacks = true,
      diffview = true,
    },
    mappings = {
      status = {
        ['<cr>'] = 'TabOpen',
      },
    },
  }

  loaded = true
end

function M.setup()
  vim.api.nvim_create_user_command('Neogit', function(opts)
    M.ensure_loaded()
    local neogit = require 'neogit'
    neogit.open(require('neogit.lib.util').parse_command_args(opts.fargs))
  end, {
    nargs = '*',
    bang = true,
  })

  vim.keymap.set('n', '<leader>gg', function()
    M.ensure_loaded()
    local neogit = require 'neogit'
    neogit.open { cwd = neogit_cwd() }
  end, { desc = 'Git status' })
end

return M
