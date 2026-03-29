-- Git diff UI
-- https://github.com/sindrets/diffview.nvim
return {
  'sindrets/diffview.nvim',
  dependencies = { 'nvim-lua/plenary.nvim' },
  cmd = {
    'DiffviewOpen',
    'DiffviewClose',
    'DiffviewToggleFiles',
    'DiffviewFocusFiles',
    'DiffviewFileHistory',
  },
  keys = {
    {
      '<leader>gd',
      function()
        require('custom.diffview_pr_review').open()
      end,
      desc = 'Git [D]iff vs merge-base (swapped)',
    },
    { '<leader>gD', '<cmd>DiffviewClose<CR>', desc = 'Git [D]iff view close' },
    { '<leader>gf', '<cmd>DiffviewFileHistory %<CR>', desc = 'Git [F]ile history' },
    { '<leader>gF', '<cmd>DiffviewFileHistory<CR>', desc = 'Git repo [F]ile history' },
  },
  opts = function(_, opts)
    opts = opts or {}
    opts.keymaps = opts.keymaps or {}
    opts.keymaps.view = opts.keymaps.view or {}

    table.insert(opts.keymaps.view, {
      'n',
      '<leader>ic',
      function()
        require('custom.inline_review_comment').open(false, 'comment')
      end,
      { desc = 'GitHub inline review comment' },
    })

    table.insert(opts.keymaps.view, {
      'x',
      '<leader>ic',
      function()
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'nx', false)
        vim.schedule(function()
          require('custom.inline_review_comment').open(true, 'comment')
        end)
      end,
      { desc = 'GitHub inline review comment' },
    })

    table.insert(opts.keymaps.view, {
      'n',
      '<leader>ia',
      function()
        require('custom.inline_review_comment').open(false, 'approve')
      end,
      { desc = 'GitHub approve PR with comment' },
    })

    table.insert(opts.keymaps.view, {
      'x',
      '<leader>ia',
      function()
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'nx', false)
        vim.schedule(function()
          require('custom.inline_review_comment').open(true, 'approve')
        end)
      end,
      { desc = 'GitHub approve PR with comment' },
    })

    table.insert(opts.keymaps.view, {
      'n',
      '<leader>id',
      function()
        require('custom.diffview_delta_preview').open()
      end,
      { desc = 'Delta preview for current Diffview file' },
    })

    return opts
  end,
}
