local M = {}

function M.setup()
  local group = vim.api.nvim_create_augroup('nvim-next-lsp-keymaps', { clear = true })

  vim.api.nvim_create_autocmd('LspAttach', {
    group = group,
    desc = 'Set LSP buffer-local keymaps',
    callback = function(event)
      local opts = { buffer = event.buf }

      vim.keymap.set('n', 'gd', vim.lsp.buf.definition, vim.tbl_extend('force', opts, {
        desc = 'LSP: Go to definition',
      }))

      vim.keymap.set('n', 'gh', vim.lsp.buf.hover, vim.tbl_extend('force', opts, {
        desc = 'LSP: Hover',
      }))

      vim.keymap.set('n', 'gr', function()
        require('snacks').picker.lsp_references()
      end, vim.tbl_extend('force', opts, {
        desc = 'LSP: List references',
      }))

      vim.keymap.set('n', '<leader>xl', function()
        vim.diagnostic.setloclist { open = true }
      end, vim.tbl_extend('force', opts, {
        desc = 'Diagnostics: Buffer list',
      }))

      vim.keymap.set('n', '<leader>xx', function()
        vim.diagnostic.setqflist { open = true }
      end, vim.tbl_extend('force', opts, {
        desc = 'Diagnostics: Workspace list',
      }))
    end,
  })
end

return M
