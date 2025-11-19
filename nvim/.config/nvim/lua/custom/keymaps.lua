-- Custom keymaps
-- This file contains all custom keybindings separate from init.lua

-- In normal buffers: q -> open netrw in this file's directory
vim.keymap.set('n', 'q', '<cmd>Ex<CR>', { noremap = true, silent = true })

-- LSP keymaps
vim.keymap.set('n', 'gd', vim.lsp.buf.definition, { desc = 'LSP: Go to definition' })
vim.keymap.set('n', 'gh', vim.lsp.buf.hover, { desc = 'LSP: Hover (preview)' })
vim.keymap.set('n', 'gr', vim.lsp.buf.references, { desc = 'LSP: List references' })
