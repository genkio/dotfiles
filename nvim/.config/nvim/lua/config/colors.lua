local M = {}

function M.setup()
  require('tokyonight').setup({
    style = 'storm',
    light_style = 'storm',
  })

  -- Keep the background-aware entrypoint so light mode uses `light_style`.
  vim.cmd.colorscheme 'tokyonight'
end

return M
