local M = {}

function M.setup()
  local gitsigns = require 'gitsigns'

  gitsigns.setup {
    signs = {
      add = { text = '+' },
      change = { text = '~' },
      delete = { text = '_' },
      topdelete = { text = '‾' },
      changedelete = { text = '~' },
    },
    current_line_blame = false,
  }

  local map = vim.keymap.set

  map('n', 'gc', function()
    if vim.wo.diff then
      vim.cmd.normal { ']c', bang = true }
      return
    end

    gitsigns.next_hunk()
  end, { desc = 'Next hunk' })

  map('n', 'gC', function()
    if vim.wo.diff then
      vim.cmd.normal { '[c', bang = true }
      return
    end

    gitsigns.prev_hunk()
  end, { desc = 'Previous hunk' })

  map('n', '<leader>gp', gitsigns.preview_hunk, { desc = 'Git preview hunk' })
  map('n', '<leader>gb', gitsigns.blame_line, { desc = 'Git blame line' })
  map('n', '<leader>gB', require('config.github_pr').open_current_line_pr, { desc = 'GitHub PR for blamed line' })
end

return M
