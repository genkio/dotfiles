vim.opt_local.wrap = true
vim.opt_local.linebreak = true
vim.opt_local.breakindent = true

local function by_display_line(key)
  return function()
    return vim.v.count == 0 and ('g' .. key) or key
  end
end

vim.keymap.set({ 'n', 'x' }, 'j', by_display_line('j'), { buffer = 0, expr = true, desc = 'Down by display line' })
vim.keymap.set({ 'n', 'x' }, 'k', by_display_line('k'), { buffer = 0, expr = true, desc = 'Up by display line' })
vim.keymap.set({ 'n', 'x' }, '$', by_display_line('$'), { buffer = 0, expr = true, desc = 'End of display line' })
vim.keymap.set({ 'n', 'x' }, '^', by_display_line('^'), { buffer = 0, expr = true, desc = 'First non-blank of display line' })
