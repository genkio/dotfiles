--[[
return {
  'NickvanDyke/opencode.nvim',
  dependencies = {
    -- Recommended for `ask()` and `select()`.
    -- Required for `snacks` provider.
    ---@module 'snacks' <- Loads `snacks.nvim` types for configuration intellisense.
    {
      'folke/snacks.nvim',
      opts = {
        input = {},
        picker = {},
        terminal = {},
      },
    },
  },
  config = function()
    ---@type opencode.Opts
    vim.g.opencode_opts = {
      provider = {
        enabled = vim.env.TMUX and 'tmux' or 'terminal',
        tmux = {
          options = '-v', -- Vertical split (side by side)
        },
        terminal = {
          split = 'right',
        },
      },
    }

    -- Required for `opts.events.reload`
    vim.o.autoread = true

    -- Register which-key group for opencode
    require('which-key').add {
      { '<leader>o', group = '[O]pencode' },
    }

    -- Opencode keymaps
    vim.keymap.set({ 'n', 'x' }, '<leader>oo', function()
      require('opencode').ask('@this: ', { submit = true })
    end, { desc = 'Ask [O]pencode' })

    vim.keymap.set({ 'n', 'x' }, '<leader>oc', function()
      require('opencode').ask('@this ', { submit = false })
    end, { desc = 'Add [C]ontext (accumulate)' })

    vim.keymap.set({ 'n', 'x' }, '<leader>om', function()
      require('opencode').select()
    end, { desc = 'Action [M]enu' })

    vim.keymap.set({ 'n', 'x' }, '<leader>ol', function()
      require('opencode').command 'session.list'
    end, { desc = '[L]ist sessions' })

    -- Toggle opencode pane
    vim.keymap.set({ 'n', 't' }, '<leader>ox', function()
      require('opencode').toggle()
    end, { desc = 'Toggle/Close opencode' })

    vim.keymap.set({ 'n', 'x' }, 'go', function()
      return require('opencode').operator '@this '
    end, { expr = true, desc = 'Add range to opencode' })
    vim.keymap.set('n', 'goo', function()
      return require('opencode').operator '@this ' .. '_'
    end, { expr = true, desc = 'Add line to opencode' })

    vim.keymap.set('n', '<S-C-u>', function()
      require('opencode').command 'session.half.page.up'
    end, { desc = 'opencode half page up' })
    vim.keymap.set('n', '<S-C-d>', function()
      require('opencode').command 'session.half.page.down'
    end, { desc = 'opencode half page down' })
  end,
}
--]]

return {}
