local M = {}

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

function M.setup()
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
  }

  vim.keymap.set('n', '<leader>gg', function()
    neogit.open { cwd = neogit_cwd() }
  end, { desc = 'Git status' })
end

return M
