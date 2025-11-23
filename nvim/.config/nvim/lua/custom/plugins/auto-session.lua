-- Auto session management - saves and restores sessions per project directory
-- https://github.com/rmagatti/auto-session

return {
  'rmagatti/auto-session',
  lazy = false,
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
