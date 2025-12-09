-- Aerial.nvim - Code outline window for skimming and quick navigation
-- https://github.com/stevearc/aerial.nvim

return {
  'stevearc/aerial.nvim',
  dependencies = {
    'nvim-treesitter/nvim-treesitter',
    'nvim-tree/nvim-web-devicons',
  },
  opts = {
    -- Priority list of preferred backends for aerial
    -- Use treesitter first for better performance, fallback to LSP
    backends = { 'treesitter', 'lsp', 'markdown', 'asciidoc', 'man' },

    -- Layout and appearance
    layout = {
      max_width = { 40, 0.2 }, -- 40 cols or 20% of editor width, whichever is smaller
      width = nil, -- Use max_width setting
      min_width = 20,
      default_direction = 'prefer_right', -- Open on right side
      placement = 'window', -- 'window' or 'edge'
    },

    -- Show box drawings for hierarchy
    show_guides = true,

    -- Automatically close aerial when you select a symbol
    close_on_select = false,

    -- Highlight the closest symbol to cursor
    highlight_on_hover = true,

    -- Jump to symbol in source with cursor
    autojump = false,

    -- Keymaps in aerial window
    keymaps = {
      ['<CR>'] = 'actions.jump',
      ['<C-v>'] = 'actions.jump_vsplit',
      ['<C-s>'] = 'actions.jump_split',
      ['o'] = 'actions.tree_toggle',
      ['O'] = 'actions.tree_toggle_recursive',
      ['za'] = 'actions.tree_toggle',
      ['zA'] = 'actions.tree_toggle_recursive',
      ['q'] = 'actions.close',
      ['zr'] = 'actions.tree_increase_fold_level',
      ['zR'] = 'actions.tree_open_all',
      ['zm'] = 'actions.tree_decrease_fold_level',
      ['zM'] = 'actions.tree_close_all',
      ['{'] = 'actions.prev',
      ['}'] = 'actions.next',
      ['[['] = 'actions.prev_up',
      [']]'] = 'actions.next_up',
    },

    -- Automatically open aerial when entering supported buffers
    open_automatic = false,

    -- Enable telescope integration
    -- This allows using :Telescope aerial to search symbols
    on_attach = function(bufnr)
      -- Buffer-local keymaps for quick navigation
      vim.keymap.set('n', '{', '<cmd>AerialPrev<CR>', { buffer = bufnr, desc = 'Aerial: Previous symbol' })
      vim.keymap.set('n', '}', '<cmd>AerialNext<CR>', { buffer = bufnr, desc = 'Aerial: Next symbol' })
    end,

    -- Filter which symbols to show
    filter_kind = {
      'Class',
      'Constructor',
      'Enum',
      'Function',
      'Interface',
      'Module',
      'Method',
      'Struct',
      'Type',
      'Variable',
      'Constant',
      'Field',
      'Property',
    },
  },
  keys = {
    -- Toggle aerial window
    { '<leader>a', '<cmd>AerialToggle!<CR>', desc = 'Toggle [A]erial outline' },
    -- Open aerial and jump to location
    { '<leader>A', '<cmd>AerialOpen<CR>', desc = 'Open [A]erial outline' },
    -- Navigate symbols with telescope (if telescope is available)
    {
      '<leader>so',
      function()
        require('telescope').extensions.aerial.aerial()
      end,
      desc = '[S]earch [O]utline (Aerial)',
    },
  },
  config = function(_, opts)
    require('aerial').setup(opts)

    -- Enable telescope integration if available
    pcall(function()
      require('telescope').load_extension('aerial')
    end)
  end,
}
