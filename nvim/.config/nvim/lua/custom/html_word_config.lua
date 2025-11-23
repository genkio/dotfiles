-- Make hyphen (-) part of a word for HTML-like files
-- This allows ciw to work on component names like <some-comp>

local html_filetypes = {
  'html',
  'xml',
  'javascriptreact',
  'typescriptreact',
  'vue',
  'svelte',
}

for _, ft in ipairs(html_filetypes) do
  vim.api.nvim_create_autocmd('FileType', {
    pattern = ft,
    callback = function()
      -- Add hyphen to iskeyword so it's treated as part of a word
      vim.opt_local.iskeyword:append '-'
    end,
    desc = 'Include hyphen in word definition for ' .. ft,
  })
end
