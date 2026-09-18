vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

vim.o.wrap = false
vim.o.mouse = 'a'
vim.o.number = true
vim.o.relativenumber = true
vim.o.cursorline = true
vim.o.cursorlineopt = 'number,screenline'
vim.o.confirm = true
vim.o.undofile = true
vim.o.scrolloff = 10
vim.o.sidescrolloff = 10
vim.o.updatetime = 250
vim.o.signcolumn = 'yes'
vim.o.inccommand = 'split'
vim.o.termguicolors = true
vim.o.list = true
vim.opt.listchars = {
  tab = '  ',
  trail = '+',
}
vim.opt.iskeyword:append '-'
vim.opt.clipboard:append 'unnamedplus'

vim.o.tabstop = 2
vim.o.shiftwidth = 2
vim.o.softtabstop = 2
vim.o.expandtab = true
vim.o.smartindent = true

vim.o.splitright = true
vim.o.splitbelow = true

vim.o.ignorecase = true
vim.o.smartcase = true

local dotfiles_root = require('config.paths').dotfiles_root

local function detect_ssh()
  if vim.env.SSH_CONNECTION or vim.env.SSH_CLIENT or vim.env.SSH_TTY then
    return true
  end
  if vim.env.TMUX then
    local result = vim.system({ 'tmux', 'show-environment', 'SSH_CONNECTION' }, { text = true }):wait()
    if result.code == 0 and result.stdout and result.stdout:match '^SSH_CONNECTION=%S' then
      return true
    end
  end
  return false
end

local is_ssh = detect_ssh()
local osc52_helper = vim.fs.joinpath(dotfiles_root, 'tmux', 'bin', 'osc52-copy.sh')

if is_ssh and vim.env.TMUX and vim.fn.executable(osc52_helper) == 1 then
  local clipboard_cache = {
    ['+'] = { lines = {}, regtype = 'v' },
    ['*'] = { lines = {}, regtype = 'v' },
  }

  local function make_copy(reg)
    return function(lines, regtype)
      clipboard_cache[reg] = {
        lines = vim.deepcopy(lines),
        regtype = regtype,
      }

      vim.system({ osc52_helper }, {
        stdin = table.concat(lines, '\n'),
        text = true,
      }, function(result)
        if result.code == 0 then
          return
        end

        vim.schedule(function()
          vim.notify(
            string.format('Clipboard copy failed via %s (exit %d)', osc52_helper, result.code),
            vim.log.levels.WARN
          )
        end)
      end)
    end
  end

  local function make_paste(reg)
    return function()
      local cached = clipboard_cache[reg]
      return { cached.lines or {}, cached.regtype or 'v' }
    end
  end

  vim.g.clipboard = {
    name = 'osc52-tmux-helper',
    copy = {
      ['+'] = make_copy '+',
      ['*'] = make_copy '*',
    },
    paste = {
      ['+'] = make_paste '+',
      ['*'] = make_paste '*',
    },
    cache_enabled = 0,
  }
elseif is_ssh then
  vim.g.clipboard = 'osc52'
end

vim.env.NVIM_SHELL_ALIASES = '1'
vim.env.ZDOTDIR = vim.fs.joinpath(dotfiles_root, 'zsh')

vim.pack.add({
  { src = 'https://github.com/nuvic/flexoki-nvim', version = 'main' },
  { src = 'https://github.com/folke/tokyonight.nvim', version = 'main' },
  { src = 'https://github.com/folke/flash.nvim', version = 'main' },
  { src = 'https://github.com/folke/snacks.nvim', version = 'main' },
  { src = 'https://github.com/folke/which-key.nvim', version = 'main' },
  { src = 'https://github.com/lewis6991/gitsigns.nvim', version = 'v1.0.0' },
}, { confirm = false })

require('config.colors').setup()
require('config.auto_reload').setup()
require('config.auto_save').setup()
require('config.copy_range').setup()
require('config.directory_resume').setup()
require('config.flash').setup()
require('config.gitsigns').setup()
require('config.lazygit').setup()
require('config.lsp_keymaps').setup()
require('config.markdown_vault').setup()
require('config.netrw').setup()
require('config.quit').setup()
require('config.reflow').setup()
require('config.restore_cursor').setup()
require('config.search_count').setup()
require('config.search_highlight').setup()
require('config.snacks').setup()
require('config.statusline').setup()
require('config.which_key').setup()
require('config.yank_highlight').setup()

vim.lsp.enable 'ts_ls'
