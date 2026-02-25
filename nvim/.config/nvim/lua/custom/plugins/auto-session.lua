-- Auto session management - saves and restores sessions per project directory
-- https://github.com/rmagatti/auto-session

return {
  'rmagatti/auto-session',
  lazy = false,
  init = function()
    local group = vim.api.nvim_create_augroup('custom-autosession-swapexists', { clear = true })
    vim.api.nvim_create_autocmd('SwapExists', {
      group = group,
      desc = 'Skip swap prompts while auto-session is restoring',
      callback = function()
        local ok, autosession = pcall(require, 'auto-session')
        if ok and autosession.restore_in_progress then
          vim.v.swapchoice = 'e'
        end
      end,
    })
  end,
  opts = {
    -- Automatically save session on exit and restore on startup
    auto_save_enabled = true,
    auto_restore_enabled = true,

    -- Sessions are saved per directory (cwd)
    -- When you open nvim in a directory, it restores that directory's session
    auto_session_use_git_branch = false,

    -- Suppress session restore/save messages
    auto_session_suppress_dirs = {
      '~/',
      '~/Downloads',
      '~/Documents',
      '~/Desktop',
      '/tmp',
    },

    -- Save session on exit
    auto_session_enable_last_session = false,

    -- Only restore session if opening nvim without file arguments
    -- This prevents restoring when you do "nvim file.txt"
    args_allow_single_directory = true,

    -- Keep auto-save enabled if a stale swap file appears during restore
    restore_error_handler = function(error_msg)
      if type(error_msg) == 'string' then
        -- Treat stale swap files and missing local cwd paths as recoverable restore errors.
        if string.find(error_msg, 'E325', 1, true) or string.find(error_msg, 'E344', 1, true) then
          return true
        end
      end
      return require('auto-session').default_restore_error_handler(error_msg)
    end,

    -- Make sure restore keeps going even if one command inside a session file fails.
    continue_restore_on_error = true,

    -- Don't save/restore certain buffer types
    bypass_session_save_file_types = {
      'gitcommit',
      'gitrebase',
    },

    -- Hook to prevent saving empty sessions
    pre_save_cmds = {
      -- Close netrw buffers before saving (they don't restore well)
      function()
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
          if vim.bo[buf].filetype == 'netrw' then
            vim.api.nvim_buf_delete(buf, { force = true })
          end
        end
      end,
    },

    -- Commands you can use:
    -- :SessionSave - manually save current session
    -- :SessionRestore - manually restore session for cwd
    -- :SessionDelete - delete session for cwd
    -- :Autosession search - search and load a session
    -- :Autosession delete - search and delete a session
  },
}
