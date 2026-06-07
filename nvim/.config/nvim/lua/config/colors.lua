local M = {}

local function detect_macos_background()
  local helper = require('config.paths').join('scripts', 'current-theme.sh')
  local result = vim.fn.system({ helper })
  if vim.v.shell_error == 0 and result:match('dark') then
    return 'dark'
  end
  return 'light'
end

-- Light mode uses Flexoki (its `dawn` variant); dark mode uses TokyoNight
-- Storm, matching the terminal's Flexoki Light / TokyoNight Storm so the
-- editor surface stays seamless with the terminal.
local function pick_scheme()
  return vim.o.background == 'light' and 'flexoki' or 'tokyonight-storm'
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
    -- Copy Normal's background onto EndOfBuffer so the whole editor surface is one shade.
    local normal = vim.api.nvim_get_hl(0, { name = 'Normal' })
    local eob = vim.api.nvim_get_hl(0, { name = 'EndOfBuffer' })
    vim.api.nvim_set_hl(0, 'EndOfBuffer', {
      ctermfg = eob.ctermfg,
      ctermbg = normal.ctermbg,
      fg = eob.fg,
      bg = normal.bg,
    })
    vim.api.nvim_set_hl(0, 'Search', {
      ctermfg = 16,
      ctermbg = 116,
      fg = '#000000',
      bg = '#87d7d7',
    })
    return
  end

  -- `flexoki` (nuvic/flexoki-nvim) follows `vim.o.background`; in light mode it
  -- renders the `dawn` variant matching the terminal's `Flexoki Light`.
  -- `enable.terminal` is left off on purpose: the plugin's terminal_color
  -- export mislabels green/blue/cyan, so `:terminal` buffers (e.g. the LazyGit
  -- launcher) use Nvim's default ANSI palette instead.
  require('flexoki').setup({
    variant = 'auto',
  })
  -- `tokyonight-storm` (folke/tokyonight.nvim) is the dark scheme, matching
  -- the terminal's `TokyoNight Storm`.
  require('tokyonight').setup({
    style = 'storm',
  })

  vim.o.background = detect_macos_background()
  vim.cmd.colorscheme(pick_scheme())

  -- Both schemes read `background` only when applied, so re-pick whenever
  -- `:set background=...` toggles at runtime.
  vim.api.nvim_create_autocmd('OptionSet', {
    pattern = 'background',
    callback = function()
      vim.cmd.colorscheme(pick_scheme())
    end,
  })

  -- Re-detect and apply the effective theme. Cheap + idempotent: the OptionSet
  -- autocmd only re-picks the colorscheme when `background` actually flips.
  local function refresh()
    local desired = detect_macos_background()
    if vim.o.background ~= desired then
      vim.o.background = desired
    end
  end

  -- Re-check macOS appearance on refocus. Nvim has no native hook for
  -- system appearance changes, so this catches real light/dark toggles that
  -- happened while another app held focus.
  vim.api.nvim_create_autocmd('FocusGained', { callback = refresh })

  -- The ctrl+alt+cmd+t hotkey flips ~/.cache/dotfiles/theme-override without
  -- touching macOS appearance, so neither AppleInterfaceThemeChangedNotification
  -- nor FocusGained fires while nvim keeps focus. Watch the cache dir so the
  -- colorscheme follows the override the instant theme-toggle.sh rewrites it.
  -- Dir-level (not file-level) watch keeps firing across delete-on-revert.
  local uv = vim.uv or vim.loop
  local cache_dir = (vim.env.XDG_CACHE_HOME or (vim.env.HOME .. '/.cache')) .. '/dotfiles'
  vim.fn.mkdir(cache_dir, 'p')
  local watcher = uv.new_fs_event()
  if watcher then
    watcher:start(cache_dir, {}, function(err, filename)
      if err then
        return
      end
      if filename == nil or filename == 'theme-override' then
        vim.schedule(refresh)
      end
    end)
    vim.api.nvim_create_autocmd('VimLeavePre', {
      callback = function()
        pcall(function()
          watcher:stop()
        end)
      end,
    })
  end
end

return M
