-- Git diff UI
-- https://github.com/sindrets/diffview.nvim
return {
  'sindrets/diffview.nvim',
  dependencies = { 'nvim-lua/plenary.nvim' },
  cmd = {
    'DiffviewOpen',
    'DiffviewClose',
    'DiffviewToggleFiles',
    'DiffviewFocusFiles',
    'DiffviewFileHistory',
  },
  keys = {
    {
      '<leader>gd',
      function()
        local group = vim.api.nvim_create_augroup('custom-diffview-swap', { clear = false })

        -- Workaround: Diffview keeps old/new ordering fixed (A left, B right).
        -- After opening with `--imply-local`, swap A/B windows to show local on the left.
        vim.api.nvim_create_autocmd('User', {
          group = group,
          pattern = 'DiffviewViewOpened',
          once = true,
          callback = function()
            local ok, lib = pcall(require, 'diffview.lib')
            if not ok then
              return
            end

            local view = lib.get_current_view()
            local layout = view and view.cur_layout or nil
            if not (layout and layout.a and layout.b) then
              return
            end

            local win_a = layout.a.id
            local win_b = layout.b.id
            if not (vim.api.nvim_win_is_valid(win_a) and vim.api.nvim_win_is_valid(win_b)) then
              return
            end

            local pos_a = vim.api.nvim_win_get_position(win_a)
            local pos_b = vim.api.nvim_win_get_position(win_b)

            local should_swap = false
            if layout.name == 'diff2_horizontal' then
              should_swap = pos_a[2] < pos_b[2]
            elseif layout.name == 'diff2_vertical' then
              should_swap = pos_a[1] < pos_b[1]
            end

            if should_swap then
              vim.api.nvim_win_call(win_a, function()
                vim.cmd 'wincmd x'
              end)
            end
          end,
        })

        vim.cmd 'DiffviewOpen origin/HEAD...HEAD --imply-local'
      end,
      desc = 'Git [D]iff vs merge-base (swapped)',
    },
    { '<leader>gD', '<cmd>DiffviewClose<CR>', desc = 'Git [D]iff view close' },
    { '<leader>gf', '<cmd>DiffviewFileHistory %<CR>', desc = 'Git [F]ile history' },
    { '<leader>gF', '<cmd>DiffviewFileHistory<CR>', desc = 'Git repo [F]ile history' },
  },
  opts = {},
}
