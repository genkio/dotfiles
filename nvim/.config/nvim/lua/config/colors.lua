local M = {}

function M.setup()
  -- macOS Terminal.app advertises xterm-256color but does not support
  -- truecolor or report its background via OSC 11, so tokyonight degrades to
  -- a washed-out, low-contrast palette. Fall back to a 256-color built-in
  -- that ships with proper cterm definitions for both light and dark profiles.
  if vim.env.TERM_PROGRAM == 'Apple_Terminal' then
    -- Terminal.app's default Basic profile is a light theme (white bg). It
    -- doesn't support truecolor, so tokyonight degrades poorly. Fall back to
    -- a built-in light 256-color scheme so embedded UIs (lazygit, terminal
    -- buffers) inherit a white backdrop where ANSI blues stay readable.
    vim.o.termguicolors = false
    vim.o.background = 'light'
    vim.cmd.colorscheme 'morning'
    return
  end

  require('tokyonight').setup({
    style = 'storm',
    light_style = 'day',
  })

  -- Keep the background-aware entrypoint so light mode uses `light_style`.
  vim.cmd.colorscheme 'tokyonight'
end

return M
