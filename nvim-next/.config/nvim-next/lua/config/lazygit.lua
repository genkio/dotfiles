local M = {}

local function override_config_path(kind)
  return '/tmp/nvim-next-lazygit-' .. kind .. '.yml'
end

local function delta_config_path()
  return '/tmp/nvim-next-delta.gitconfig'
end

local function ensure_delta_config()
  local path = delta_config_path()
  vim.fn.writefile({
    '[delta]',
    'dark = true',
    'paging = never',
    'line-numbers = true',
    'hyperlinks = true',
    'hyperlinks-file-link-format = lazygit-edit://{path}:{line}',
    'syntax-theme = Monokai Extended',
    'minus-style = "syntax #3b2240"',
    'plus-style = "syntax #1f3a32"',
  }, path)
  return path
end

local function ensure_override_config(kind)
  local lines = {
    'gui:',
    '  showCommandLog: false',
  }

  if kind == 'compact' then
    vim.list_extend(lines, {
      '  screenMode: half',
      '  portraitMode: auto',
      '  enlargedSideViewLocation: top',
      '  expandFocusedSidePanel: true',
      '  expandedSidePanelWeight: 4',
      '  mainPanelSplitMode: flexible',
      '  showPanelJumps: false',
    })
  end

  table.insert(lines, 'promptToReturnFromSubprocess: false')

  if vim.fn.executable 'delta' == 1 then
    vim.list_extend(lines, {
      'git:',
      '  pagers:',
      '    - pager: delta --config=' .. delta_config_path(),
    })
    ensure_delta_config()
  end

  local path = override_config_path(kind)
  vim.fn.writefile(lines, path)
  return path
end

local function lazygit_command(kind)
  local command = { 'lazygit' }

  if kind == 'compact' then
    vim.list_extend(command, { '--screen-mode', 'half' })
  end

  vim.list_extend(command, {
    '--use-config-file',
    ensure_override_config(kind),
  })

  return command
end

local function open(kind)
  vim.cmd.tabnew()
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].bufhidden = 'wipe'

  vim.fn.termopen(lazygit_command(kind), {
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

function M.open()
  open 'compact'
end

function M.open_default()
  open 'default'
end

function M.setup()
  vim.api.nvim_create_user_command('LazyGit', M.open, {
    desc = 'Open LazyGit with the default layout',
  })

  vim.keymap.set('n', '<leader>lg', M.open_default, { desc = 'LazyGit default layout' })
  vim.keymap.set('n', '<leader>lG', M.open, { desc = 'LazyGit compact layout' })
end

return M
