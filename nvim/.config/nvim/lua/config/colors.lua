local M = {}

local function pick_scheme()
  return vim.o.background == 'light' and 'dawnfox' or 'nordfox'
end

local function detect_macos_background()
  local result = vim.fn.system({ 'defaults', 'read', '-g', 'AppleInterfaceStyle' })
  if vim.v.shell_error == 0 and result:match('Dark') then
    return 'dark'
  end
  return 'light'
end

function M.setup()
  -- macOS Terminal.app advertises xterm-256color but does not support
  -- truecolor or report its background via OSC 11, so truecolor schemes
  -- degrade to a washed-out, low-contrast palette. Fall back to a
  -- 256-color built-in that ships with proper cterm definitions.
  if vim.env.TERM_PROGRAM == 'Apple_Terminal' then
    vim.o.termguicolors = false
    vim.o.background = 'light'
    vim.cmd.colorscheme 'morning'
    return
  end

  vim.o.background = detect_macos_background()
  require('nightfox').setup({})
  vim.cmd.colorscheme(pick_scheme())

  -- Swap fox variants when `:set background=...` toggles at runtime.
  vim.api.nvim_create_autocmd('OptionSet', {
    pattern = 'background',
    callback = function()
      vim.cmd.colorscheme(pick_scheme())
    end,
  })

  -- Re-check macOS appearance on refocus. Nvim has no native hook for
  -- system appearance changes, so this catches toggles that happened
  -- while another app held focus.
  vim.api.nvim_create_autocmd('FocusGained', {
    callback = function()
      local desired = detect_macos_background()
      if vim.o.background ~= desired then
        vim.o.background = desired
      end
    end,
  })
end

return M
