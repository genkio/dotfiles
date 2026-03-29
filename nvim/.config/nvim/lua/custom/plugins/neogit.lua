-- Git status UI
-- https://github.com/NeogitOrg/neogit
return {
  'NeogitOrg/neogit',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'sindrets/diffview.nvim',
  },
  cmd = 'Neogit',
  keys = {
    { '<leader>gg', '<cmd>Neogit<CR>', desc = 'Git status' },
  },
  opts = {
    builders = {
      NeogitDiffPopup = function(builder)
        local has_diff_viewer = require('neogit.config').get_diff_viewer() ~= nil

        builder
          :new_action_group 'Review'
          :action_if(has_diff_viewer, 'm', 'merge-base PR', function(popup)
            popup:close()
            require('custom.diffview_pr_review').open()
          end)
      end,
    },
  },
}
