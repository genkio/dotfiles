local M = {}

local root_markers = {
  '.obsidian',
  'logseq/config.edn',
}

local function detect_vault_root(path)
  if path == '' then
    return nil
  end

  local start = vim.fs.normalize(path)
  if vim.fn.isdirectory(start) ~= 1 then
    start = vim.fs.dirname(start)
  end

  local marker = vim.fs.find(root_markers, {
    path = start,
    upward = true,
    limit = 1,
  })[1]

  if not marker then
    return nil
  end

  local normalized = vim.fs.normalize(marker)
  if normalized:sub(-#'/logseq/config.edn') == '/logseq/config.edn' then
    return vim.fs.dirname(vim.fs.dirname(normalized))
  end

  return vim.fs.dirname(normalized)
end

local function file_exists(path)
  return vim.uv.fs_stat(path) ~= nil
end

local function escape_glob(text)
  return (text:gsub('([%*%?%[%]%{%}\\, ])', '\\%1'))
end

local function note_matches(root, target)
  local patterns = {}
  local escaped = escape_glob(target)

  if target:match '%.%w+$' then
    patterns = {
      '**/' .. escaped,
    }
  else
    patterns = {
      '**/' .. escaped .. '.md',
      '**/' .. escaped .. '/index.md',
    }
  end

  local matches = {}
  for _, pattern in ipairs(patterns) do
    for _, path in ipairs(vim.fn.globpath(root, pattern, false, true)) do
      matches[path] = true
    end
  end

  local paths = vim.tbl_keys(matches)
  table.sort(paths)
  return paths
end

local function parse_wikilink()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  local init = 1

  while true do
    local start_col, end_col = line:find('%[%[.-%]%]', init)
    if not start_col then
      return nil
    end

    if col >= start_col and col <= end_col then
      return vim.trim(line:sub(start_col + 2, end_col - 2))
    end

    init = end_col + 1
  end
end

local function parse_target(raw_link)
  local link = raw_link:match '^[^|]+' or raw_link
  local target, anchor = link:match '^(.-)#(.+)$'

  if not target then
    target = link
  end

  target = vim.trim(target)
  anchor = anchor and vim.trim(anchor) or nil

  if target == '' then
    return nil, nil
  end

  return target, anchor
end

local function parse_tag()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  local init = 1

  while true do
    local start_col, end_col = line:find('#[%w_/%-]+', init)
    if not start_col then
      return nil
    end

    if col >= start_col and col <= end_col then
      return line:sub(start_col + 1, end_col)
    end

    init = end_col + 1
  end
end

local function search_anchor(anchor)
  if not anchor or anchor == '' then
    return
  end

  local pattern = '\\V' .. vim.fn.escape(anchor, '\\')
  vim.fn.search(pattern, 'cw')
  vim.cmd 'normal! zzzv'
end

local function open_note(path, anchor)
  vim.cmd('edit ' .. vim.fn.fnameescape(path))
  search_anchor(anchor)
end

local function resolve_target_path(target, origin, root)
  if target:sub(1, 1) == '/' then
    local absolute = vim.fs.normalize(root .. target)
    if not absolute:match '%.%w+$' then
      absolute = absolute .. '.md'
    end
    if file_exists(absolute) then
      return { absolute }
    end
  end

  if target:find '/' then
    local relative = vim.fs.normalize(vim.fs.dirname(origin) .. '/' .. target)
    if not relative:match '%.%w+$' then
      relative = relative .. '.md'
    end
    if file_exists(relative) then
      return { relative }
    end

    local rooted = vim.fs.normalize(root .. '/' .. target)
    if not rooted:match '%.%w+$' then
      rooted = rooted .. '.md'
    end
    if file_exists(rooted) then
      return { rooted }
    end
  end

  return note_matches(root, target)
end

function M.follow_link()
  local origin = vim.api.nvim_buf_get_name(0)
  local root = detect_vault_root(origin)
  local raw_link = parse_wikilink()

  if not (root and raw_link) then
    return false
  end

  local target, anchor = parse_target(raw_link)
  if not target then
    return false
  end

  local matches = resolve_target_path(target, origin, root)
  if #matches == 0 then
    vim.notify('No note found for [[' .. target .. ']]', vim.log.levels.WARN)
    return true
  end

  if #matches == 1 then
    open_note(matches[1], anchor)
    return true
  end

  vim.ui.select(matches, {
    prompt = 'Select note',
    format_item = function(path)
      return vim.fs.relpath(root, path) or path
    end,
  }, function(choice)
    if choice then
      open_note(choice, anchor)
    end
  end)

  return true
end

function M.find_backlinks()
  local path = vim.api.nvim_buf_get_name(0)
  local root = detect_vault_root(path)

  if not root then
    return false
  end

  local note_name = vim.fn.fnamemodify(path, ':t:r')
  require('telescope.builtin').grep_string {
    cwd = root,
    search = '[[' .. note_name,
    use_regex = false,
    prompt_title = 'Backlinks: ' .. note_name,
    additional_args = function()
      return { '--glob', '*.md' }
    end,
  }

  return true
end

function M.find_tag_references(tag)
  local path = vim.api.nvim_buf_get_name(0)
  local root = detect_vault_root(path)
  local current_tag = tag or parse_tag()

  if not (root and current_tag) then
    return false
  end

  require('telescope.builtin').grep_string {
    cwd = root,
    search = '#' .. current_tag,
    use_regex = false,
    prompt_title = 'Tag: ' .. current_tag,
    additional_args = function()
      return { '--glob', '*.md' }
    end,
  }

  return true
end

function M.follow_tag()
  local origin = vim.api.nvim_buf_get_name(0)
  local root = detect_vault_root(origin)
  local tag = parse_tag()

  if not (root and tag) then
    return false
  end

  local matches = resolve_target_path(tag, origin, root)
  if #matches == 1 then
    open_note(matches[1])
    return true
  end

  if #matches > 1 then
    vim.ui.select(matches, {
      prompt = 'Select tag page',
      format_item = function(path)
        return vim.fs.relpath(root, path) or path
      end,
    }, function(choice)
      if choice then
        open_note(choice)
      end
    end)
    return true
  end

  return M.find_tag_references(tag)
end

function M.goto_definition()
  if M.follow_link() then
    return
  end

  if M.follow_tag() then
    return
  end

  if #vim.lsp.get_clients { bufnr = 0 } > 0 then
    vim.lsp.buf.definition()
    return
  end

  local ok = pcall(vim.cmd, 'normal! gf')
  if not ok then
    vim.notify('No wiki link or file under cursor', vim.log.levels.WARN)
  end
end

function M.show_references()
  if M.find_tag_references() then
    return
  end

  if M.find_backlinks() then
    return
  end

  require('telescope.builtin').lsp_references()
end

function M.setup()
  local group = vim.api.nvim_create_augroup('custom-markdown-vault', { clear = true })

  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = 'markdown',
    desc = 'Enable note navigation inside Obsidian/Logseq-style vaults',
    callback = function(event)
      local path = vim.api.nvim_buf_get_name(event.buf)
      if not detect_vault_root(path) then
        return
      end

      vim.keymap.set('n', 'gd', M.goto_definition, {
        buffer = event.buf,
        desc = 'Notes: Follow link',
      })
      vim.keymap.set('n', 'gr', M.show_references, {
        buffer = event.buf,
        desc = 'Notes: Find references',
      })
    end,
  })
end

M._detect_vault_root = detect_vault_root

return M
