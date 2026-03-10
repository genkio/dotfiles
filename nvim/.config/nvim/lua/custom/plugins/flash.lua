-- Enhanced jump/search motions
-- https://github.com/folke/flash.nvim

return {
  'folke/flash.nvim',
  event = 'VeryLazy',
  ---@type Flash.Config
  opts = {},
  keys = {
    {
      's',
      mode = { 'n', 'x', 'o' },
      function()
        require('flash').jump()
      end,
      desc = 'Flash',
    },
  },
}
