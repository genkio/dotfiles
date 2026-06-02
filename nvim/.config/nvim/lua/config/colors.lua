local M = {}

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

  -- Flexoki (nuvic/flexoki-nvim). The `flexoki` colorscheme follows
  -- `vim.o.background`, rendering the `dawn` (light) or `moon` (dark)
  -- variant. Its palette matches Ghostty's bundled `Flexoki Light` /
  -- `Flexoki Dark` themes so the editor surface is seamless with the
  -- terminal.
  --
  -- `enable.terminal` is left off on purpose: the plugin's terminal_color
  -- export mislabels green/blue/cyan, so `:terminal` buffers (e.g. the
  -- LazyGit launcher) use Nvim's default ANSI palette instead.
  require('flexoki').setup({
    variant = 'auto',
  })

  vim.o.background = detect_macos_background()
  vim.cmd.colorscheme('flexoki')

  -- flexoki reads `background` only when the colorscheme is applied, so
  -- re-apply it whenever `:set background=...` toggles at runtime to swap
  -- the dawn/moon variant.
  vim.api.nvim_create_autocmd('OptionSet', {
    pattern = 'background',
    callback = function()
      vim.cmd.colorscheme('flexoki')
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
