-- LazyGit terminal launcher with per-invocation override configs.
--
-- The keymaps open LazyGit in a disposable tab terminal, hiding the command log
-- by default and optionally applying a compact layout for smaller screens. When
-- delta is available, a temporary config also wires LazyGit's pager to delta so
-- file links can jump back into Neovim.

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

local function osc52_copy_helper()
  return vim.fn.expand '~/dotfiles/tmux/bin/osc52-copy.sh'
end

local function ensure_delta_config()
  local path = delta_config_path()
  local apple_terminal = vim.env.TERM_PROGRAM == 'Apple_Terminal'
  local lines
  if apple_terminal then
    -- Terminal.app lacks truecolor; truecolor styles render as muddy near-blue
    -- tones on the light Basic profile. Use a light-theme syntax + ANSI-named
    -- diff backgrounds so labels stay legible on white.
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

-- Lazygit executes copyToClipboardCmd directly via argv (no shell), so a pipe
-- in the YAML wouldn't work. Drop a tiny wrapper that bridges the {{text}} arg
-- to osc52-copy.sh's stdin (OSC52 works over SSH + tmux; mirrors to pbcopy locally).
local function ensure_osc52_clip_script()
  local copy_helper = osc52_copy_helper()
  if vim.fn.executable(copy_helper) ~= 1 then
    return nil
  end

  local path = osc52_clip_path()
  vim.fn.writefile({
    '#!/usr/bin/env bash',
    'set -euo pipefail',
    '',
    'text=${1:-}',
    'if [ -z "$text" ]; then',
    '  text=$(cat)',
    'fi',
    '',
    string.format('printf -- \'%%s\' "$text" | %s', copy_helper),
  }, path)
  return path
end

local function ensure_override_config(kind, opts)
  opts = opts or {}
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
      [[    command: 'nvim --server "$NVIM" --remote-expr ''execute("LazyGitQuitAll")''']],
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

  if kind == 'compact' then
    vim.list_extend(command, { '--screen-mode', 'half' })
  end

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

  vim.fn.termopen(lazygit_command(kind, opts), {
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

function M.open_quit_all()
  open('default', { quit_nvim_on_Q = true })
end

function M.quit_all()
  local has_unsaved = false
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].modified and vim.bo[buf].buflisted and vim.bo[buf].buftype == '' then
      has_unsaved = true
      break
    end
  end

  if not has_unsaved then
    vim.cmd 'qa!'
    return
  end

  local choice = vim.fn.confirm('Unsaved changes. Quit anyway?', '&Save all\n&Discard\n&Cancel', 3)

  if choice == 1 then
    pcall(vim.cmd, 'wall')
    vim.cmd 'qa!'
  elseif choice == 2 then
    vim.cmd 'qa!'
  end
end

function M.setup()
  vim.api.nvim_create_user_command('LazyGit', M.open, {
    desc = 'Open LazyGit with the default layout',
  })
  vim.api.nvim_create_user_command('LazyGitQuitAll', M.quit_all, {
    desc = 'Quit lazygit and Neovim (prompts on unsaved buffers)',
  })

  vim.keymap.set('n', '<leader>lg', M.open_default, { desc = 'LazyGit default layout' })
  vim.keymap.set('n', '<leader>lG', M.open, { desc = 'LazyGit compact layout' })
end

return M
