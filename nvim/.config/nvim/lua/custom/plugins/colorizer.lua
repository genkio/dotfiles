-- Highlight color codes like #rrggbb inline
-- https://github.com/norcalli/nvim-colorizer.lua

return {
  'norcalli/nvim-colorizer.lua',
  event = { 'BufReadPre', 'BufNewFile' },
  config = function()
    local colorizer = require 'colorizer'
    local group = vim.api.nvim_create_augroup('UserColorizer', { clear = true })

    -- Avoid the plugin's deprecated setup() path and attach directly.
    vim.api.nvim_create_autocmd('FileType', {
      group = group,
      callback = function(args)
        if vim.bo[args.buf].buftype == '' then
          colorizer.attach_to_buffer(args.buf)
        end
      end,
    })

    local current_buf = vim.api.nvim_get_current_buf()
    if vim.bo[current_buf].filetype ~= '' and vim.bo[current_buf].buftype == '' then
      colorizer.attach_to_buffer(current_buf)
    end
  end,
}
