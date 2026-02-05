-- Adds git related signs to the gutter, as well as utilities for managing changes
-- NOTE: gitsigns is already included in init.lua but contains only the base
-- config. This will add also the recommended keymaps.

return {
  {
    'lewis6991/gitsigns.nvim',
    opts = {
      gh = true,
      current_line_blame = true, -- Show blame info inline on current line
      current_line_blame_opts = {
        virt_text = true,
        virt_text_pos = 'eol', -- 'eol' | 'overlay' | 'right_align'
        delay = 300, -- delay in ms before showing blame
      },
      on_attach = function(bufnr)
        local gitsigns = require 'gitsigns'

        local function map(mode, l, r, opts)
          opts = opts or {}
          opts.buffer = bufnr
          vim.keymap.set(mode, l, r, opts)
        end

        local function resolve_main_base()
          local bufname = vim.api.nvim_buf_get_name(bufnr)
          local dir = bufname ~= '' and vim.fn.fnamemodify(bufname, ':p:h') or vim.fn.getcwd()

          local function git_out(args)
            local cmd = { 'git', '-C', dir }
            vim.list_extend(cmd, args)
            local out = vim.fn.systemlist(cmd)
            if vim.v.shell_error ~= 0 then
              return nil
            end
            return out
          end

          local function git_ok(args)
            local cmd = { 'git', '-C', dir }
            vim.list_extend(cmd, args)
            vim.fn.system(cmd)
            return vim.v.shell_error == 0
          end

          local head = git_out { 'symbolic-ref', '--quiet', '--short', 'refs/remotes/origin/HEAD' }
          if head and head[1] and head[1] ~= '' then
            return head[1]
          end

          for _, name in ipairs { 'main', 'master', 'origin/main', 'origin/master' } do
            if git_ok { 'rev-parse', '--verify', '--quiet', name } then
              return name
            end
          end
        end

        -- Navigation
        map('n', ']c', function()
          if vim.wo.diff then
            vim.cmd.normal { ']c', bang = true }
          else
            gitsigns.nav_hunk 'next'
          end
        end, { desc = 'Jump to next git [c]hange' })

        map('n', '[c', function()
          if vim.wo.diff then
            vim.cmd.normal { '[c', bang = true }
          else
            gitsigns.nav_hunk 'prev'
          end
        end, { desc = 'Jump to previous git [c]hange' })

        -- Actions
        -- visual mode
        map('v', '<leader>hs', function()
          gitsigns.stage_hunk { vim.fn.line '.', vim.fn.line 'v' }
        end, { desc = 'git [s]tage hunk' })
        map('v', '<leader>hr', function()
          gitsigns.reset_hunk { vim.fn.line '.', vim.fn.line 'v' }
        end, { desc = 'git [r]eset hunk' })
        -- normal mode
        map('n', '<leader>hs', gitsigns.stage_hunk, { desc = 'git [s]tage hunk' })
        map('n', '<leader>hr', gitsigns.reset_hunk, { desc = 'git [r]eset hunk' })
        map('n', '<leader>hS', gitsigns.stage_buffer, { desc = 'git [S]tage buffer' })
        map('n', '<leader>hu', gitsigns.stage_hunk, { desc = 'git [u]ndo stage hunk' })
        map('n', '<leader>hR', gitsigns.reset_buffer, { desc = 'git [R]eset buffer' })
        map('n', '<leader>hp', gitsigns.preview_hunk, { desc = 'git [p]review hunk' })
        map('n', '<leader>hb', gitsigns.blame_line, { desc = 'git [b]lame line' })
        map('n', '<leader>hB', function()
          gitsigns.blame_line { full = true }
        end, { desc = 'git [B]lame line (full)' })
        map('n', '<leader>hd', gitsigns.diffthis, { desc = 'git [d]iff against index' })
        map('n', '<leader>hD', function()
          gitsigns.diffthis '@'
        end, { desc = 'git [D]iff against last commit' })
        map('n', '<leader>hm', function()
          local base = resolve_main_base()
          if not base then
            vim.notify('Could not find main/master to diff against', vim.log.levels.WARN)
            return
          end
          gitsigns.diffthis(base, { vertical = true })
        end, { desc = 'git diff against [m]ain/master' })
        -- Toggles
        map('n', '<leader>tb', gitsigns.toggle_current_line_blame, { desc = '[T]oggle git show [b]lame line' })
        map('n', '<leader>tD', gitsigns.preview_hunk_inline, { desc = '[T]oggle git show [D]eleted' })
      end,
    },
  },
}
