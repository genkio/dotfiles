-- Auto-save markdown and plain-text buffers, but only when Neovim was launched
-- with a single file argument (e.g. `nvim ~/notes/draft.md`). Directory
-- launches such as bare `vi` (which the zsh alias rewrites to `nvim .`) or
-- `vi some/folder/` leave this off so the normal browse-and-edit workflow is
-- unaffected.
--
-- When active, the buffer is written on InsertLeave, TextChanged, and
-- FocusLost so notes survive crashes or reboots without needing a manual `:w`.

local M = {}

local function launched_with_single_file()
  if vim.fn.argc() ~= 1 then
    return false
  end

  local arg = vim.fn.argv(0)
  if type(arg) ~= 'string' or arg == '' then
    return false
  end

  return vim.fn.isdirectory(arg) ~= 1
end

local function buffer_savable(buf)
  if vim.bo[buf].buftype ~= '' then
    return false
  end
  if vim.bo[buf].readonly or not vim.bo[buf].modifiable then
    return false
  end
  if vim.api.nvim_buf_get_name(buf) == '' then
    return false
  end
  return vim.bo[buf].modified
end

function M.setup()
  if not launched_with_single_file() then
    return
  end

  local group = vim.api.nvim_create_augroup('nvim-next-auto-save', { clear = true })

  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = { 'markdown', 'text' },
    desc = 'Attach auto-save to markdown and text buffers in single-file sessions',
    callback = function(event)
      vim.api.nvim_create_autocmd({ 'InsertLeave', 'TextChanged', 'FocusLost' }, {
        group = group,
        buffer = event.buf,
        desc = 'Auto-save buffer',
        callback = function()
          if not buffer_savable(event.buf) then
            return
          end
          vim.api.nvim_buf_call(event.buf, function()
            vim.cmd 'silent! write'
          end)
        end,
      })
    end,
  })
end

return M
