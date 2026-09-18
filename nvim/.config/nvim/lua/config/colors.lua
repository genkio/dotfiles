local M = {}

local function detect_macos_background()
  local helper = require('config.paths').join('scripts', 'current-theme.sh')
  local result = vim.fn.system({ helper })
  if vim.v.shell_error == 0 and result:match('dark') then
    return 'dark'
  end
  return 'light'
end

local function pick_scheme()
  return vim.o.background == 'light' and 'flexoki' or 'tokyonight-storm'
end

function M.setup()
  if vim.env.TERM_PROGRAM == 'Apple_Terminal' then
    vim.o.termguicolors = false
    vim.o.background = 'light'
    vim.cmd.colorscheme 'morning'
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

  require('flexoki').setup({
    variant = 'auto',
  })
  require('tokyonight').setup({
    style = 'storm',
  })

  vim.o.background = detect_macos_background()
  vim.cmd.colorscheme(pick_scheme())

  vim.api.nvim_create_autocmd('OptionSet', {
    pattern = 'background',
    callback = function()
      vim.cmd.colorscheme(pick_scheme())
    end,
  })

  local function refresh()
    local desired = detect_macos_background()
    if vim.o.background ~= desired then
      vim.o.background = desired
    end
  end

  vim.api.nvim_create_autocmd('FocusGained', { callback = refresh })

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
