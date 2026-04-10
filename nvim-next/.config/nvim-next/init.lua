-- Fresh Neovim 0.12 sandbox launched with:
--   NVIM_APPNAME=nvim-next nvim
--
-- Keep this config intentionally small. Add only what earns its place.

-- Use <space> as the leader key
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- General
vim.o.wrap = false
vim.o.mouse = 'a' -- enable mouse support
vim.o.number = true -- show line numbers
vim.o.relativenumber = true
vim.o.confirm = true -- raise dialog asking if you wish to save the current file
vim.o.undofile = true -- save undo history
vim.o.scrolloff = 10 -- keep 10 lines above/below cursor
vim.o.sidescrolloff = 10 -- keep 10 lines to left/right cursor
vim.o.updatetime = 250 -- decrease update time
vim.o.signcolumn = 'yes' -- prevent gutter once diagnostics and lsp signs show up
vim.o.inccommand = 'split' -- preview substitutions live as you type
vim.o.termguicolors = true -- enable 24-bit rgb color in the terminal
-- use .opt instead of .o to get option object instead or lua string
vim.opt.iskeyword:append '-' -- include - in-words
vim.opt.clipboard:append 'unnamedplus' -- use system clipboard

-- Tabs and indentation
vim.o.tabstop = 2
vim.o.shiftwidth = 2
vim.o.softtabstop = 2
vim.o.expandtab = true
vim.o.smartindent = true

-- Split
vim.o.splitright = true
vim.o.splitbelow = true

-- Search
vim.o.ignorecase = true -- case insensitive search
vim.o.smartcase = true -- case sensitive search if uppercase in string

require('config.colors').setup()

-- Plugins
vim.pack.add({
  { src = 'https://github.com/folke/flash.nvim', version = 'main' },
  { src = 'https://github.com/folke/snacks.nvim', version = 'main' },
  { src = 'https://github.com/folke/which-key.nvim', version = 'main' },
  { src = 'https://github.com/nvim-lua/plenary.nvim', version = 'master' },
  { src = 'https://github.com/NeogitOrg/neogit', version = 'master' },
  { src = 'https://github.com/sindrets/diffview.nvim', version = 'main' },
}, { confirm = false })

require('config.auto_reload').setup()
require('config.copy_range').setup()
require('config.directory_resume').setup()
require('config.diffview').setup()
require('config.flash').setup()
require('config.lsp_keymaps').setup()
require('config.neogit').setup()
require('config.snacks').setup()
require('config.which_key').setup()

vim.lsp.enable 'ts_ls'
