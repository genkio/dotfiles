local M = {}

function M.setup()
  local wk = require 'which-key'

  wk.setup {
    delay = 0,
    icons = {
      mappings = false,
    },
    triggers = {
      { '<leader>', mode = { 'n', 'x' } },
    },
    plugins = {
      marks = false,
      registers = false,
      spelling = {
        enabled = false,
      },
      presets = {
        operators = false,
        motions = false,
        text_objects = false,
        windows = false,
        nav = false,
        z = false,
        g = false,
      },
    },
    spec = {
      { '<leader>e', group = 'Explorer' },
      { '<leader>g', group = 'Git' },
      { '<leader>l', group = 'LazyGit' },
      { '<leader>s', group = 'Search', mode = { 'n', 'x' } },
      { '<leader>x', group = 'Diagnostics' },
      { '<leader>y', group = 'Yank' },
    },
  }

  vim.keymap.set('n', '<leader>?', function()
    wk.show { global = false }
  end, { desc = 'Show buffer keymaps' })
end

return M
