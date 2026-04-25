-- Fresh Neovim 0.12 sandbox launched with:
--   NVIM_APPNAME=nvim-next nvim
--
-- Keep this config intentionally small. Add only what earns its place.

-- Use <space> as the leader key
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- General
vim.o.wrap = false
vim.o.mouse = 'a' -- enable mouse support
vim.o.number = true -- show line numbers
vim.o.relativenumber = true
vim.o.confirm = true -- raise dialog asking if you wish to save the current file
vim.o.undofile = true -- save undo history
vim.o.scrolloff = 10 -- keep 10 lines above/below cursor
vim.o.sidescrolloff = 10 -- keep 10 lines to left/right cursor
vim.o.updatetime = 250 -- decrease update time
vim.o.signcolumn = 'yes' -- prevent gutter once diagnostics and lsp signs show up
vim.o.inccommand = 'split' -- preview substitutions live as you type
vim.o.termguicolors = true -- enable 24-bit rgb color in the terminal
vim.o.list = true -- show trailing spaces
-- use .opt instead of .o to get option object instead or lua string
vim.opt.listchars = {
  tab = '  ',
  trail = '+',
}
vim.opt.iskeyword:append '-' -- include - in-words
vim.opt.clipboard:append 'unnamedplus' -- use system clipboard locally, OSC52 over SSH

-- Tabs and indentation
vim.o.tabstop = 2
vim.o.shiftwidth = 2
vim.o.softtabstop = 2
vim.o.expandtab = true
vim.o.smartindent = true

-- Split
vim.o.splitright = true
vim.o.splitbelow = true

-- Search
vim.o.ignorecase = true -- case insensitive search
vim.o.smartcase = true -- case sensitive search if uppercase in string

require('config.colors').setup()

local resolved_config_dir = vim.fn.resolve(vim.fn.stdpath 'config')
local dotfiles_root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(resolved_config_dir)))

local is_ssh = vim.env.SSH_CONNECTION or vim.env.SSH_CLIENT or vim.env.SSH_TTY
local osc52_helper = vim.fs.joinpath(dotfiles_root, 'tmux', 'bin', 'osc52-copy.sh')

if is_ssh and vim.env.TMUX and vim.fn.executable(osc52_helper) == 1 then
  local clipboard_cache = {
    ['+'] = { lines = {}, regtype = 'v' },
    ['*'] = { lines = {}, regtype = 'v' },
  }

  local function make_copy(reg)
    return function(lines, regtype)
      clipboard_cache[reg] = {
        lines = vim.deepcopy(lines),
        regtype = regtype,
      }

      vim.system({ osc52_helper }, {
        stdin = table.concat(lines, '\n'),
        text = true,
      }, function(result)
        if result.code == 0 then
          return
        end

        vim.schedule(function()
          vim.notify(
            string.format('Clipboard copy failed via %s (exit %d)', osc52_helper, result.code),
            vim.log.levels.WARN
          )
        end)
      end)
    end
  end

  local function make_paste(reg)
    return function()
      local cached = clipboard_cache[reg]
      return { cached.lines or {}, cached.regtype or 'v' }
    end
  end

  vim.g.clipboard = {
    name = 'osc52-tmux-helper',
    copy = {
      ['+'] = make_copy '+',
      ['*'] = make_copy '*',
    },
    paste = {
      ['+'] = make_paste '+',
      ['*'] = make_paste '*',
    },
    cache_enabled = 0,
  }
elseif is_ssh then
  -- Over SSH on macOS, Neovim prefers pbcopy unless we force OSC52.
  vim.g.clipboard = 'osc52'
end

-- Mark shells spawned by Neovim so zsh can load command helpers like `gpu()`
-- from `.zshenv` without requiring a full interactive shell startup.
vim.env.NVIM_SHELL_ALIASES = '1'
vim.env.ZDOTDIR = vim.fs.joinpath(dotfiles_root, 'zsh')

-- Plugins
vim.pack.add({
  { src = 'https://github.com/folke/flash.nvim', version = 'main' },
  { src = 'https://github.com/folke/snacks.nvim', version = 'main' },
  { src = 'https://github.com/folke/which-key.nvim', version = 'main' },
  { src = 'https://github.com/lewis6991/gitsigns.nvim', version = 'v1.0.0' },
  { src = 'https://github.com/nvim-lua/plenary.nvim', version = 'master' },
}, { confirm = false })

vim.pack.add({
  { src = 'https://github.com/sindrets/diffview.nvim', version = 'main' },
}, {
  confirm = false,
  load = function()
    -- Keep Diffview installed but unloaded until first use.
  end,
})

require('config.auto_reload').setup()
require('config.copy_range').setup()
require('config.directory_resume').setup()
require('config.diffview').setup()
require('config.flash').setup()
require('config.gitsigns').setup()
require('config.lazygit').setup()
require('config.lsp_keymaps').setup()
require('config.markdown_vault').setup()
require('config.netrw').setup()
require('config.restore_cursor').setup()
require('config.search_highlight').setup()
require('config.snacks').setup()
require('config.statusline').setup()
require('config.which_key').setup()

vim.lsp.enable 'ts_ls'
