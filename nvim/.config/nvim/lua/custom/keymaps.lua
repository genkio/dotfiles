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

-- Auto-import: trigger code action filtered for import actions
vim.keymap.set('n', '<leader>ci', function()
  vim.lsp.buf.code_action {
    filter = function(action)
      return action.kind and string.match(action.kind, 'source%.addMissingImports')
    end,
    apply = true,
  }
end, { desc = 'LSP: Add missing imports' })

-- Organize imports
vim.keymap.set('n', '<leader>co', function()
  vim.lsp.buf.code_action {
    filter = function(action)
      return action.kind and string.match(action.kind, 'source%.organizeImports')
    end,
    apply = true,
  }
end, { desc = 'LSP: Organize imports' })

-- Quick import for symbol under cursor (like VSCode Ctrl+.)
vim.keymap.set('n', '<leader>ca', function()
  vim.lsp.buf.code_action {
    filter = function(action)
      -- Filter for import-related actions or all quickfix actions
      return action.kind and (
        string.match(action.kind, 'quickfix') or
        string.match(action.kind, 'refactor%.rewrite%.import')
      )
    end,
  }
end, { desc = 'LSP: Code action (imports)' })
local function lsp_def_in(split_cmd)
  return function()
    vim.cmd(split_cmd)
    vim.lsp.buf.definition()
  end
end
vim.keymap.set('n', '<leader>dv', lsp_def_in 'vsplit', { desc = 'LSP: Definition in vsplit' })
vim.keymap.set('n', '<leader>dh', lsp_def_in 'split', { desc = 'LSP: Definition in hsplit' })
vim.keymap.set('n', 'gh', vim.lsp.buf.hover, { desc = 'LSP: Hover (preview)' })
vim.keymap.set('n', 'gr', function()
  require('telescope.builtin').lsp_references()
end, { desc = 'LSP: List references' })
vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename, { desc = 'LSP: Rename symbol' })
vim.keymap.set('n', '<leader>rf', function()
  local buf = vim.api.nvim_get_current_buf()
  local ts_client = nil
  for _, client in ipairs(vim.lsp.get_active_clients { bufnr = buf }) do
    if client.name == 'ts_ls' or client.name == 'tsserver' then
      ts_client = client
      break
    end
  end
  if not ts_client then
    vim.notify('No TypeScript LSP attached', vim.log.levels.WARN)
    return
  end

  local old_name = vim.api.nvim_buf_get_name(buf)
  local new_name = vim.fn.input('New filename: ', old_name, 'file')
  if new_name == '' or new_name == old_name then
    return
  end

  local params = {
    command = '_typescript.applyRenameFile',
    arguments = {
      {
        sourceUri = vim.uri_from_fname(old_name),
        targetUri = vim.uri_from_fname(new_name),
      },
    },
  }

  ts_client.request('workspace/executeCommand', params, function(err, res)
    if err then
      vim.schedule(function()
        vim.notify('LSP rename failed: ' .. err.message, vim.log.levels.ERROR)
      end)
      return
    end
    if res then
      vim.lsp.util.apply_workspace_edit(res, ts_client.offset_encoding)
    end

    local ok, rename_err = os.rename(old_name, new_name)
    if not ok then
      vim.schedule(function()
        vim.notify('File move failed: ' .. rename_err, vim.log.levels.ERROR)
      end)
      return
    end

    vim.schedule(function()
      vim.cmd('edit ' .. vim.fn.fnameescape(new_name))
    end)
  end)
end, { desc = 'LSP: Rename file (ts)' })
