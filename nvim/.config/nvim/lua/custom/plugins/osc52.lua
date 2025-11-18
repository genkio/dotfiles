return {
  'ojroques/nvim-osc52',
  config = function()
    require('osc52').setup {
      max_length = 0, -- Maximum length of selection (0 for no limit)
      silent = false, -- Disable message on successful copy
      trim = false, -- Trim surrounding whitespaces before copy
    }

    -- Auto-copy to clipboard on yank when over SSH
    if os.getenv 'SSH_CONNECTION' then
      vim.api.nvim_create_autocmd('TextYankPost', {
        callback = function()
          if vim.v.event.operator == 'y' then
            require('osc52').copy_register '"'
          end
        end,
      })
    end
  end,
}
