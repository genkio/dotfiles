local M = {}

local function override_config_path()
  return '/tmp/nvim-next-lazygit.yml'
end

local function ensure_override_config()
  local lines = {
    'gui:',
    '  screenMode: half',
    '  portraitMode: auto',
    '  enlargedSideViewLocation: top',
    '  expandFocusedSidePanel: true',
    '  expandedSidePanelWeight: 4',
    '  mainPanelSplitMode: flexible',
    '  showCommandLog: false',
    'promptToReturnFromSubprocess: false',
  }

  if vim.fn.executable 'delta' == 1 then
    vim.list_extend(lines, {
      'git:',
      '  pagers:',
      '    - pager: delta --dark --paging=never --line-numbers --hyperlinks --hyperlinks-file-link-format=lazygit-edit://{path}:{line}',
    })
  end

  local path = override_config_path()
  vim.fn.writefile(lines, path)
  return path
end

local function lazygit_command()
  return {
    'lazygit',
    '--screen-mode',
    'half',
    '--use-config-file',
    ensure_override_config(),
  }
end

function M.open()
  vim.cmd.tabnew()
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].bufhidden = 'wipe'

  vim.fn.termopen(lazygit_command(), {
    cwd = vim.fn.getcwd(),
    on_exit = function()
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then
          return
        end

        for _, win in ipairs(vim.fn.win_findbuf(buf)) do
          if vim.api.nvim_win_is_valid(win) then
            pcall(vim.api.nvim_win_close, win, true)
          end
        end
      end)
    end,
  })
  vim.cmd.startinsert()
end

function M.setup()
  vim.api.nvim_create_user_command('LazyGit', M.open, {
    desc = 'Open LazyGit in a new tab terminal',
  })

  vim.keymap.set('n', '<leader>lg', M.open, { desc = 'LazyGit' })
end

return M
