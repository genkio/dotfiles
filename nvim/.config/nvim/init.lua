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

local paths = require 'config.paths'
local dotfiles_root = paths.dotfiles_root

local clip = paths.join('scripts', 'clip.sh')
if vim.fn.executable(clip) == 1 then
  local paste = vim.fn.executable 'pbpaste' == 1 and { 'pbpaste' } or function()
    return vim.split(vim.fn.getreg '"', '\n')
  end
  vim.g.clipboard = {
    name = 'clip',
    copy = { ['+'] = { clip }, ['*'] = { clip } },
    paste = { ['+'] = paste, ['*'] = paste },
    cache_enabled = 1,
  }
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
