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
        -- Open PR for blamed commit
        map('n', '<leader>ho', function()
          local blame = vim.b.gitsigns_blame_line_dict
          if not blame or not blame.sha or blame.sha:match '^0+$' then
            vim.notify('No blame info for this line (uncommitted?)', vim.log.levels.WARN)
            return
          end
          local sha = blame.sha

          -- Parse remote URL into a base web URL
          local function get_remote_info()
            local remote = vim.trim(vim.fn.system { 'git', 'remote', 'get-url', 'origin' }
            )
            if vim.v.shell_error ~= 0 or remote == '' then
              return nil
            end
            -- Normalize SSH and HTTPS URLs to https://host/org/repo
            local host, path
            -- SSH: git@host:org/repo.git or ssh://git@host/org/repo.git
            host, path = remote:match 'git@([^:]+):(.+)'
            if not host then
              host, path = remote:match 'ssh://[^@]*@([^/]+)/(.+)'
            end
            if not host then
              host, path = remote:match 'https?://([^/]+)/(.+)'
            end
            if not host or not path then
              return nil
            end
            path = path:gsub('%.git$', '')
            local base_url = 'https://' .. host .. '/' .. path
            local is_bitbucket = host:find 'bitbucket' ~= nil
            return { base_url = base_url, is_bitbucket = is_bitbucket }
          end

          local remote_info = get_remote_info()

          -- GitHub: try gh CLI for PR lookup first
          if remote_info and not remote_info.is_bitbucket then
            local pr_json = vim.fn.system { 'gh', 'pr', 'list', '--search', sha, '--state', 'merged', '--json', 'url', '--limit', '1' }
            if vim.v.shell_error == 0 then
              local ok, parsed = pcall(vim.json.decode, pr_json)
              if ok and parsed and #parsed > 0 then
                vim.ui.open(parsed[1].url)
                return
              end
            end
            -- Fallback: GitHub commit page
            vim.ui.open(remote_info.base_url .. '/commit/' .. sha)
            return
          end

          -- Bitbucket: construct commit URL directly
          if remote_info and remote_info.is_bitbucket then
            vim.ui.open(remote_info.base_url .. '/commits/' .. sha)
            return
          end

          vim.notify('Could not determine remote URL for ' .. sha:sub(1, 8), vim.log.levels.WARN)
        end, { desc = 'git [o]pen PR for blamed line' })

        -- Toggles
        map('n', '<leader>tb', gitsigns.toggle_current_line_blame, { desc = '[T]oggle git show [b]lame line' })
        map('n', '<leader>tD', gitsigns.preview_hunk_inline, { desc = '[T]oggle git show [D]eleted' })
      end,
    },
  },
}
