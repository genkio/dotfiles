-- Highlight color codes like #rrggbb inline
-- https://github.com/norcalli/nvim-colorizer.lua

return {
  'norcalli/nvim-colorizer.lua',
  event = { 'BufReadPre', 'BufNewFile' },
  config = function()
    require('colorizer').setup()
  end,
}
