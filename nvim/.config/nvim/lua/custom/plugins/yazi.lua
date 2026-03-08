local mobile_width_breakpoint = 100

local function yazi_config_home(profile)
  local xdg_config_home = vim.fs.dirname(vim.fn.stdpath('config'))
  local name = profile == 'mobile' and 'yazi-mobile' or 'yazi'

  return xdg_config_home .. '/' .. name
end

local function use_mobile_profile()
  return vim.o.columns < mobile_width_breakpoint
end

local function current_path()
  local path = vim.api.nvim_buf_get_name(0)

  if path ~= '' then
    return vim.fs.normalize(path)
  end

  return vim.uv.cwd()
end

local function project_root(path)
  local start = path

  if vim.fn.isdirectory(start) ~= 1 then
    start = vim.fs.dirname(start)
  end

  local git_dir = vim.fs.find('.git', { path = start, upward = true })[1]
  if git_dir ~= nil then
    return vim.fs.dirname(git_dir)
  end

  return start
end

local function current_yazi_config()
  local mobile = use_mobile_profile()

  return {
    open_for_directories = true,
    change_neovim_cwd_on_close = true,
    config_home = yazi_config_home(mobile and 'mobile' or 'default'),
    floating_window_scaling_factor = mobile and { width = 1, height = 1 } or 0.9,
    keymaps = {
      show_help = '<f1>',
    },
  }
end

local function open_yazi()
  local path = current_path()
  local root = project_root(path)
  local args = nil

  if path ~= root then
    args = { reveal_path = path }
  end

  require('yazi').yazi(current_yazi_config(), root, args)
end

local function open_yazi_cwd()
  require('yazi').yazi(current_yazi_config(), vim.fn.getcwd())
end

return {
  'mikavilpas/yazi.nvim',
  event = 'VeryLazy',
  dependencies = {
    'nvim-lua/plenary.nvim',
  },
  init = function()
    vim.g.loaded_netrwPlugin = 1
  end,
  config = function()
    local group = vim.api.nvim_create_augroup('custom-yazi-profile', { clear = true })
    local yazi = require 'yazi'

    local function refresh_yazi_config()
      yazi.setup(current_yazi_config())
    end

    refresh_yazi_config()

    vim.api.nvim_create_autocmd({ 'UIEnter', 'VimResized' }, {
      group = group,
      callback = refresh_yazi_config,
      desc = 'Switch yazi profile for narrow screens',
    })
  end,
  keys = {
    { 'q', open_yazi, desc = 'Open yazi' },
    { '<leader>cw', open_yazi_cwd, desc = 'Open yazi in working directory' },
  },
}
