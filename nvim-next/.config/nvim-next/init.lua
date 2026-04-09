-- Fresh Neovim 0.12 sandbox launched with:
--   NVIM_APPNAME=nvim-next nvim
--
-- Keep this config intentionally small. Add only what earns its place.

vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

vim.pack.add({
  { src = 'https://github.com/folke/snacks.nvim', version = 'main' },
}, { confirm = false })

vim.o.updatetime = 250
vim.o.number = true
vim.o.relativenumber = true

require('config.auto_reload').setup()
require('config.directory_resume').setup()
require('config.snacks').setup()

vim.lsp.enable('ts_ls')
