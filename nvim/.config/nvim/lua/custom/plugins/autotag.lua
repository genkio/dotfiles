-- Auto close and rename HTML/XML tags
-- https://github.com/windwp/nvim-ts-autotag
--
-- Usage tips:
--   - Auto-rename works in insert mode: use `ciw` on tag name to change it
--   - `ciw` = change inner word (deletes word + enters insert mode)
--   - `cit` = change inner tag (changes content between tags)
--   - `cat` = change around tag (changes entire tag including brackets)

return {
  'windwp/nvim-ts-autotag',
  event = 'InsertEnter',
  opts = {
    opts = {
      enable_close = true, -- Auto close tags
      enable_rename = true, -- Auto rename pairs of tags
      enable_close_on_slash = false, -- Auto close on trailing </
    },
  },
}
