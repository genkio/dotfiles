-- Fresh Neovim 0.12 sandbox launched with:
--   NVIM_APPNAME=nvim-next nvim
--
-- Keep this config intentionally small. Add only what earns its place.

vim.o.number = true
vim.o.relativenumber = true

require('config.directory_resume').setup()

vim.lsp.enable('ts_ls')
