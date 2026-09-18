local M = {}

local function override_config_path(kind)
  return '/tmp/nvim-next-lazygit-' .. kind .. '.yml'
end

local function delta_config_path()
  return '/tmp/nvim-next-delta.gitconfig'
end

local function osc52_clip_path()
  return '/tmp/nvim-next-lazygit-osc52-clip.sh'
end

local function ensure_delta_config()
  local path = delta_config_path()
  local apple_terminal = vim.env.TERM_PROGRAM == 'Apple_Terminal'
  local lines
  if apple_terminal then
    lines = {
      '[delta]',
      'light = true',
      'paging = never',
      'line-numbers = true',
      'hyperlinks = true',
      'hyperlinks-file-link-format = lazygit-edit://{path}:{line}',
      'syntax-theme = GitHub',
      'minus-style = "syntax auto"',
      'plus-style = "syntax auto"',
    }
  elseif vim.o.background == 'light' then
    lines = {
      '[delta]',
      'light = true',
      'paging = never',
      'line-numbers = true',
      'hyperlinks = true',
      'hyperlinks-file-link-format = lazygit-edit://{path}:{line}',
      'syntax-theme = GitHub',
      'minus-style = "syntax #ffe1d5"',
      'plus-style = "syntax #edeecf"',
    }
  else
    lines = {
      '[delta]',
      'dark = true',
      'paging = never',
      'line-numbers = true',
      'hyperlinks = true',
      'hyperlinks-file-link-format = lazygit-edit://{path}:{line}',
      'syntax-theme = Monokai Extended',
      'minus-style = "syntax #3b2240"',
      'plus-style = "syntax #1f3a32"',
    }
  end
  vim.fn.writefile(lines, path)
  return path
end

local function ensure_osc52_clip_script()
  local path = osc52_clip_path()
  vim.fn.writefile({
    '#!/usr/bin/env bash',
    'set -euo pipefail',
    '',
    'text=${1:-}',
    'if [ -z "$text" ]; then',
    '  text=$(cat)',
    'fi',
    '[ -z "$text" ] && exit 0',
    '',
    'encoded=$(printf -- \'%s\' "$text" | base64 | tr -d \'\\r\\n\')',
    '',
    'if { : > /dev/tty; } 2>/dev/null; then',
    '  printf -- \'\\033]52;c;%s\\a\' "$encoded" > /dev/tty',
    'fi',
    '',
    'if [ -z "${SSH_CONNECTION:-}" ]; then',
    '  printf -- \'%s\' "$text" | pbcopy',
    'fi',
  }, path)
  return path
end

local function theme_lines()
  local apple_terminal = vim.env.TERM_PROGRAM == 'Apple_Terminal'
  if apple_terminal then
    return {
      '  theme:',
      '    activeBorderColor: [green, bold]',
      '    inactiveBorderColor: [default]',
      '    selectedLineBgColor: [reverse]',
    }
  elseif vim.o.background == 'light' then
    return {
      '  theme:',
      "    activeBorderColor: ['#66800b', bold]",
      "    inactiveBorderColor: ['#b7b5ac']",
      "    selectedLineBgColor: ['#e6e4d9']",
    }
  else
    return {
      '  theme:',
      "    activeBorderColor: ['#9ece6a', bold]",
      "    inactiveBorderColor: ['#545c7e']",
      "    selectedLineBgColor: ['#3b4261']",
    }
  end
end

local function ensure_override_config(kind, opts)
  opts = opts or {}
  local lines = {
    'gui:',
    '  showCommandLog: false',
  }
  vim.list_extend(lines, theme_lines())

  if kind == 'folded' then
    vim.list_extend(lines, {
      '  screenMode: normal',
      '  portraitMode: never',
      '  sidePanelWidth: 0.20',
      '  expandFocusedSidePanel: true',
      '  expandedSidePanelWeight: 20',
      '  mainPanelSplitMode: flexible',
      '  showPanelJumps: true',
    })
  end

  table.insert(lines, 'promptToReturnFromSubprocess: false')

  local osc52_clip = ensure_osc52_clip_script()
  if osc52_clip then
    vim.list_extend(lines, {
      'os:',
      '  copyToClipboardCmd: "bash ' .. osc52_clip .. ' {{text}}"',
    })
  end

  if vim.fn.executable 'delta' == 1 then
    vim.list_extend(lines, {
      'git:',
      '  pagers:',
      '    - pager: delta --config=' .. delta_config_path(),
    })
    ensure_delta_config()
  end

  if opts.quit_nvim_on_Q then
    vim.list_extend(lines, {
      'customCommands:',
      [[  - key: 'Q']],
      [[    command: 'nvim --server "$NVIM" --remote-expr ''execute("QuitAll")''']],
      [[    context: 'global']],
      [[    output: 'none']],
    })
  end

  local suffix = opts.quit_nvim_on_Q and '-quitall' or ''
  local path = override_config_path(kind .. suffix)
  vim.fn.writefile(lines, path)
  return path
end

local function lazygit_command(kind, opts)
  local command = { 'lazygit' }

  vim.list_extend(command, {
    '--use-config-file',
    ensure_override_config(kind, opts),
  })

  return command
end

local function open(kind, opts)
  vim.cmd.tabnew()
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].bufhidden = 'wipe'

  vim.fn.jobstart(lazygit_command(kind, opts), {
    term = true,
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

function M.open_folded()
  open 'folded'
end

function M.open_default()
  open 'default'
end

function M.open_quit_all()
  open('folded', { quit_nvim_on_Q = true })
end

function M.setup()
  vim.api.nvim_create_user_command('LazyGit', M.open_default, {
    desc = 'Open LazyGit with the default layout',
  })

  vim.keymap.set('n', '<leader>lg', M.open_default, { desc = 'LazyGit default layout' })
  vim.keymap.set('n', '<leader>lf', M.open_folded, { desc = 'LazyGit folded layout' })

  vim.api.nvim_create_autocmd('OptionSet', {
    pattern = 'background',
    callback = function()
      pcall(ensure_delta_config)
    end,
  })
end

return M
