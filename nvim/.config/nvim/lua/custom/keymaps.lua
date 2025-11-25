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
      local dir = vim.fn.expand '%:p:h'

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

-- Save commands (work in normal buffers and netrw):
-- ZZ: Save with auto-format, then close window (built-in Vim command)
-- ZQ: Close window without saving (built-in Vim command)
-- ZW: Save file without triggering auto-format (custom command)
vim.keymap.set('n', 'ZW', function()
  -- Temporarily disable format_on_save
  vim.g.disable_autoformat = true
  -- Save the file
  vim.cmd 'write'
  -- Re-enable format_on_save
  vim.g.disable_autoformat = false
end, { noremap = true, silent = true, desc = 'Save without auto-format' })

-- Window navigation (tmux-safe)
vim.keymap.set('n', '<leader>wh', '<C-w>h', { desc = 'Window: focus left' })
vim.keymap.set('n', '<leader>wj', '<C-w>j', { desc = 'Window: focus down' })
vim.keymap.set('n', '<leader>wk', '<C-w>k', { desc = 'Window: focus up' })
vim.keymap.set('n', '<leader>wl', '<C-w>l', { desc = 'Window: focus right' })

-- LSP keymaps
vim.keymap.set('n', 'gd', vim.lsp.buf.definition, { desc = 'LSP: Go to definition' })
local function lsp_def_in(split_cmd)
  return function()
    vim.cmd(split_cmd)
    vim.lsp.buf.definition()
  end
end
vim.keymap.set('n', '<leader>dv', lsp_def_in 'vsplit', { desc = 'LSP: Definition in vsplit' })
vim.keymap.set('n', '<leader>dh', lsp_def_in 'split', { desc = 'LSP: Definition in hsplit' })
vim.keymap.set('n', 'gh', vim.lsp.buf.hover, { desc = 'LSP: Hover (preview)' })
vim.keymap.set('n', 'gr', vim.lsp.buf.references, { desc = 'LSP: List references' })
