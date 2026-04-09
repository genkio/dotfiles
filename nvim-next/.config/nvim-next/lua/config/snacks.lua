local M = {}

local function normalize(path)
  return vim.fs.normalize(vim.fn.fnamemodify(path, ':p'))
end

local function current_cwd()
  return normalize(vim.uv.cwd() or vim.fn.getcwd())
end

local function is_dotfiles_dir(path)
  local root = normalize(vim.fn.expand '~/dotfiles')
  return path == root or vim.startswith(path, root .. '/')
end

local function base_picker_opts()
  local cwd = current_cwd()
  local opts = { cwd = cwd }

  if is_dotfiles_dir(cwd) then
    opts.hidden = true
    opts.exclude = { '.git', '.git/**' }
  end

  return opts
end

local function picker_opts(extra)
  return vim.tbl_extend('force', base_picker_opts(), extra or {})
end

local function split_csv(value)
  if not value or value == '' then
    return nil
  end

  local items = {}
  for item in value:gmatch '[^,]+' do
    item = vim.trim(item)
    if item ~= '' then
      table.insert(items, item)
    end
  end

  return #items > 0 and items or nil
end

local function prompt_optional(prompt)
  local value = vim.fn.input(prompt)
  if value == '' then
    return nil
  end

  return value
end

local function has_lsp_method(method, bufnr)
  for _, client in ipairs(vim.lsp.get_clients { bufnr = bufnr }) do
    if client:supports_method(method) then
      return true
    end
  end

  return false
end

local function path_contains(root, path)
  return path == root or vim.startswith(path, root .. '/')
end

local function current_project_path()
  local name = vim.api.nvim_buf_get_name(0)
  if name == '' then
    return current_cwd()
  end

  return normalize(name)
end

local function first_attached_buffer(client)
  for bufnr in pairs(client.attached_buffers or {}) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      return bufnr
    end
  end

  return nil
end

local function workspace_symbol_target()
  local path = current_project_path()
  local fallback = nil
  local best_buf = nil
  local best_root_len = -1

  for _, client in ipairs(vim.lsp.get_clients()) do
    if client:supports_method('workspace/symbol') then
      local bufnr = first_attached_buffer(client)
      if bufnr then
        fallback = fallback or bufnr
        local root = client.config.root_dir and normalize(client.config.root_dir) or nil
        if root and path_contains(root, path) and #root > best_root_len then
          best_root_len = #root
          best_buf = bufnr
        end
      end
    end
  end

  return best_buf or fallback
end

local function grep_prompt()
  local search = prompt_optional 'Grep search: '
  if not search then
    return
  end

  require('snacks').picker.grep(picker_opts {
    search = search,
    regex = false,
    dirs = split_csv(prompt_optional 'Dirs (comma-separated, optional): '),
    glob = split_csv(prompt_optional 'Include globs (comma-separated, optional): '),
    exclude = split_csv(prompt_optional 'Exclude globs (comma-separated, optional): '),
  })
end

local function document_symbols()
  local Snacks = require 'snacks'
  if has_lsp_method('textDocument/documentSymbol', 0) then
    Snacks.picker.lsp_symbols()
    return
  end

  Snacks.picker.treesitter()
end

local function workspace_symbols()
  local Snacks = require 'snacks'
  if has_lsp_method('workspace/symbol', 0) then
    Snacks.picker.lsp_workspace_symbols()
    return
  end

  local target_buf = workspace_symbol_target()
  if not target_buf then
    vim.notify('No attached LSP client supports workspace symbols', vim.log.levels.WARN)
    return
  end

  local lsp = require 'snacks.picker.source.lsp'
  Snacks.picker.pick {
    source = 'lsp_workspace_symbols',
    finder = function(opts, ctx)
      local filter = opts.filter[vim.bo[ctx.filter.current_buf].filetype]
      if filter == nil then
        filter = opts.filter.default
      end

      local function want(kind)
        kind = kind or 'Unknown'
        return type(filter) == 'boolean' or vim.tbl_contains(filter, kind)
      end

      local bufmap = lsp.bufmap()
      return function(cb)
        lsp.request(target_buf, 'workspace/symbol', function()
          return { query = ctx.filter.search }
        end, function(client, result)
          local items = lsp.results_to_items(client, result, {
            text_with_file = true,
            filter = function(item)
              return want(lsp.symbol_kind(item.kind))
            end,
          })

          for _, item in ipairs(items) do
            item.tree = false
            item.buf = bufmap[item.file]
            cb(item)
          end
        end)
      end
    end,
  }
end

function M.setup()
  local Snacks = require 'snacks'

  Snacks.setup {
    picker = {
      enabled = true,
    },
  }

  local map = vim.keymap.set

  map('n', '<leader>sf', function()
    Snacks.picker.files(picker_opts())
  end, { desc = 'Search files in cwd' })

  map('n', '<leader>sg', function()
    Snacks.picker.grep(picker_opts { regex = false })
  end, { desc = 'Search text in cwd' })

  map({ 'n', 'x' }, '<leader>sw', function()
    Snacks.picker.grep_word(picker_opts())
  end, { desc = 'Search current word in cwd' })

  map('n', '<leader>sG', grep_prompt, { desc = 'Search text in cwd with filters' })
  map('n', '<leader>ss', document_symbols, { desc = 'Search document symbols' })
  map('n', '<leader>sS', workspace_symbols, { desc = 'Search workspace symbols' })
  map('n', '<leader>sr', function()
    Snacks.picker.resume()
  end, { desc = 'Resume last search' })
end

return M
