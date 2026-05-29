local M = {}

local function pick_scheme()
  return vim.o.background == 'light' and 'dawnfox' or 'nordfox'
end

local function detect_macos_background()
  local helper = vim.fn.expand('~/dotfiles/scripts/current-theme.sh')
  local result = vim.fn.system({ helper })
  if vim.v.shell_error == 0 and result:match('dark') then
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
  require('nightfox').setup({
    palettes = {
      -- Softer, slightly darker warm-paper background for Dawnfox light mode.
      -- bg1 (#f2ebe0) matches the Ghostty `Dawnfox-soft` theme so the editor
      -- surface is seamless with the terminal. bg0/bg2/bg3 are darkened in step
      -- to keep float / fold / cursorline layering readable. To dial darker,
      -- lower these together with Ghostty's Dawnfox-soft `background`.
      dawnfox = {
        bg0 = '#e8e0d3', -- status line, floats
        bg1 = '#f2ebe0', -- default editor background
        bg2 = '#ece4d7', -- folds, color column
        bg3 = '#e6ddcd', -- cursor line
      },
    },
  })
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
