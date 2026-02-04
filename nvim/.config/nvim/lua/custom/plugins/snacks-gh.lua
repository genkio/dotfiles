-- GH diff usage:
--   <C-w>l  focus diff preview (right pane)
--   <C-w>w  cycle back to list/input (left pane)
--   a       add diff comment on current line
--   o       open file at exact diff line (closes picker)
--   <C-s>   submit comment from scratch buffer
return {
  "folke/snacks.nvim",
  opts = function(_, opts)
    opts = opts or {}

    opts.gh = opts.gh or {}

    opts.picker = opts.picker or {}
    opts.picker.sources = opts.picker.sources or {}
    opts.picker.sources.gh_issue = opts.picker.sources.gh_issue or {}
    opts.picker.sources.gh_pr = opts.picker.sources.gh_pr or {}
    opts.picker.sources.gh_pr.focus = "list"
    opts.picker.sources.gh_pr.win = opts.picker.sources.gh_pr.win or {}
    opts.picker.sources.gh_pr.win.list = opts.picker.sources.gh_pr.win.list or {}
    opts.picker.sources.gh_diff = opts.picker.sources.gh_diff or {}
    opts.picker.sources.gh_diff.win = opts.picker.sources.gh_diff.win or {}
    opts.picker.sources.gh_diff.win.preview = opts.picker.sources.gh_diff.win.preview or {}
    opts.picker.sources.gh_diff.win.preview.keys =
      vim.tbl_extend("force", opts.picker.sources.gh_diff.win.preview.keys or {}, {
        ["o"] = "gh_jump_cursor",
      })
    opts.picker.actions = vim.tbl_extend("force", opts.picker.actions or {}, {
      gh_jump_cursor = function(picker, item)
        local win = vim.api.nvim_get_current_win()
        local buf = vim.api.nvim_get_current_buf()
        local meta = Snacks.picker.highlight.meta(buf)
        local cursor = vim.api.nvim_win_get_cursor(win)[1]
        local m = meta and meta[cursor] or nil
        if not (m and m.diff and m.diff.file and m.diff.line) then
          Snacks.notify.error("No diff hunk found to jump to")
          return
        end

        item = item or picker:current()
        local path = require("snacks.picker.util").path({
          file = m.diff.file,
          cwd = item and item.cwd or picker:cwd(),
        })
        if not path then
          Snacks.notify.error("Could not resolve file path for diff")
          return
        end

        if picker.opts.jump.close then
          picker:close()
        else
          vim.api.nvim_set_current_win(picker.main)
        end

        vim.cmd(("edit %s"):format(vim.fn.fnameescape(path)))
        vim.api.nvim_win_set_cursor(0, { m.diff.line, 0 })
        vim.cmd("normal! zzzv")
      end,
    })
    opts.picker.win = opts.picker.win or {}
    opts.picker.win.input = opts.picker.win.input or {}
    opts.picker.win.list = opts.picker.win.list or {}
    opts.picker.win.input.keys = vim.tbl_extend("force", opts.picker.win.input.keys or {}, {
      ["<C-w>l"] = "focus_preview",
    })
    opts.picker.win.list.keys = vim.tbl_extend("force", opts.picker.win.list.keys or {}, {
      ["<C-w>l"] = "focus_preview",
    })

    return opts
  end,
  keys = {
    { "<leader>gi", function() Snacks.picker.gh_issue() end, desc = "GitHub issues (open)" },
    { "<leader>gI", function() Snacks.picker.gh_issue({ state = "all" }) end, desc = "GitHub issues (all)" },
    { "<leader>gp", function() Snacks.picker.gh_pr() end, desc = "GitHub pull requests (open)" },
    { "<leader>gP", function() Snacks.picker.gh_pr({ state = "all" }) end, desc = "GitHub pull requests (all)" },
    { "<leader>gr", function() Snacks.picker.resume() end, desc = "GitHub resume picker" },
    { "<leader>gR", function() Snacks.picker.resume({ source = "gh_diff" }) end, desc = "GitHub resume diff" },
  },
}
