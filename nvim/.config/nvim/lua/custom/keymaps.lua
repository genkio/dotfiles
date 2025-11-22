-- Custom keymaps
-- This file contains all custom keybindings separate from init.lua

-- In normal buffers: q -> open netrw in this file's directory
vim.keymap.set('n', 'q', '<cmd>Ex<CR>', { noremap = true, silent = true })

-- Netrw: Use fzf when pressing % in netrw buffers
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'netrw',
  callback = function()
    vim.keymap.set('n', '%', function()
      -- Get the current directory from netrw
      local dir = vim.fn.expand('%:p:h')

      -- Create a function to handle the fzf selection
      local function fzf_open_file()
        local tmp_file = vim.fn.tempname()
        local fzf_cmd = string.format(
          'cd %s && fzf --preview "bat --style=numbers --color=always {} 2>/dev/null || cat {}" > %s',
          vim.fn.shellescape(dir),
          vim.fn.shellescape(tmp_file)
        )

        -- Open fzf in a terminal
        vim.fn.termopen(fzf_cmd, {
          on_exit = function(_, exit_code)
            -- Close the terminal buffer
            vim.cmd 'bdelete!'

            -- Read the selected file
            if vim.fn.filereadable(tmp_file) == 1 then
              local selected_file = vim.fn.readfile(tmp_file)
              vim.fn.delete(tmp_file)

              -- Open the selected file if one was chosen (exit code 0 means selection made)
              if exit_code == 0 and #selected_file > 0 and selected_file[1] ~= '' then
                local file_path = dir .. '/' .. selected_file[1]
                vim.cmd('edit ' .. vim.fn.fnameescape(file_path))
              end
            end
          end,
        })

        -- Enter insert mode to interact with fzf
        vim.cmd 'startinsert'
      end

      -- Open fzf in a new buffer
      vim.cmd 'enew'
      fzf_open_file()
    end, { buffer = true, noremap = true, silent = true, desc = 'Open file with fzf' })
  end,
})

-- LSP keymaps
vim.keymap.set('n', 'gd', vim.lsp.buf.definition, { desc = 'LSP: Go to definition' })
vim.keymap.set('n', 'gh', vim.lsp.buf.hover, { desc = 'LSP: Hover (preview)' })
vim.keymap.set('n', 'gr', vim.lsp.buf.references, { desc = 'LSP: List references' })
