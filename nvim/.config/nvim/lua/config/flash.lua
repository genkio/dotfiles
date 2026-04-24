local M = {}

function M.setup()
  local flash = require 'flash'

  flash.setup {}

  vim.keymap.set({ 'n', 'x', 'o' }, 's', function()
    flash.jump()
  end, { desc = 'Flash jump' })
end

return M
