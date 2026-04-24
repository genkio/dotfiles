local M = {}

local root_markers = {
  '.obsidian',
  'logseq/config.edn',
}

local obsidian_app_cache = {}
local markdown_file_cache = {}
local tag_completion_cache = {}
local cache_ttl_ms = 2000

local function file_exists(path)
  return vim.uv.fs_stat(path) ~= nil
end

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

local function read_obsidian_app(root)
  if obsidian_app_cache[root] ~= nil then
    return obsidian_app_cache[root]
  end

  local path = root .. '/.obsidian/app.json'
  if not file_exists(path) then
    obsidian_app_cache[root] = false
    return nil
  end

  local lines = vim.fn.readfile(path)
  local ok, decoded = pcall(vim.json.decode, table.concat(lines, '\n'))
  if not ok or type(decoded) ~= 'table' then
    obsidian_app_cache[root] = false
    return nil
  end

  obsidian_app_cache[root] = decoded
  return decoded
end

local function escape_regex(text)
  return (text:gsub('([%^%$%(%)%%%.%[%]%*%+%-%?])', '\\%1'))
end

local function markdown_files(root)
  local now = vim.uv.now()
  local cached = markdown_file_cache[root]
  if cached and now - cached.at < cache_ttl_ms then
    return cached.paths
  end

  local paths = nil
  if vim.fn.executable 'git' == 1 and file_exists(root .. '/.git') then
    local result = vim.system({
      'git',
      '-C',
      root,
      'ls-files',
      '--cached',
      '--others',
      '--exclude-standard',
    }, { text = true }):wait()

    if result.code == 0 then
      paths = {}
      for relative in result.stdout:gmatch '[^\r\n]+' do
        if relative:match '%.md$' then
          table.insert(paths, vim.fs.normalize(root .. '/' .. relative))
        end
      end
    end
  end

  if not paths then
    paths = vim.fn.globpath(root, '**/*.md', false, true)
  end

  table.sort(paths)
  markdown_file_cache[root] = {
    at = now,
    paths = paths,
  }
  return paths
end

local function note_completion_items(root, with_closing)
  local counts = {}
  local notes = {}

  for _, path in ipairs(markdown_files(root)) do
    local basename = vim.fn.fnamemodify(path, ':t:r')
    local relative = (vim.fs.relpath(root, path) or path):gsub('%.md$', '')

    counts[basename] = (counts[basename] or 0) + 1
    table.insert(notes, {
      basename = basename,
      relative = relative,
    })
  end

  local items = {}
  for _, note in ipairs(notes) do
    local unique_basename = counts[note.basename] == 1
    local word = unique_basename and note.basename or note.relative

    table.insert(items, {
      word = word .. (with_closing and ']]' or ''),
      abbr = word,
      menu = unique_basename and note.relative ~= note.basename and note.relative or nil,
      dup = 1,
    })
  end

  return items
end

local function tag_completion_items(root)
  local now = vim.uv.now()
  local cached = tag_completion_cache[root]
  if cached and now - cached.at < cache_ttl_ms then
    return cached.items
  end

  local seen = {}
  for _, path in ipairs(markdown_files(root)) do
    for _, line in ipairs(vim.fn.readfile(path)) do
      for tag in line:gmatch '#([%w][%w_/%-]*)' do
        seen[tag] = true
      end
    end
  end

  local items = {}
  for tag in pairs(seen) do
    table.insert(items, {
      word = tag,
      abbr = '#' .. tag,
      menu = 'tag',
      dup = 1,
    })
  end

  table.sort(items, function(a, b)
    return a.word < b.word
  end)

  tag_completion_cache[root] = {
    at = now,
    items = items,
  }
  return items
end

local function note_matches(root, target, origin)
  local files = markdown_files(root)
  local allowed = {}

  for _, path in ipairs(files) do
    allowed[vim.fs.normalize(path)] = true
  end

  local matches = {}
  local function add_if_allowed(path)
    local normalized = vim.fs.normalize(path)
    if allowed[normalized] then
      matches[normalized] = true
    end
  end

  if target:sub(1, 1) == '/' then
    local absolute = vim.fs.normalize(root .. target)
    add_if_allowed(absolute)
    if not absolute:match '%.%w+$' then
      add_if_allowed(absolute .. '.md')
      add_if_allowed(absolute .. '/index.md')
    end
  elseif target:find '/' then
    local relative = vim.fs.normalize(vim.fs.dirname(origin) .. '/' .. target)
    local rooted = vim.fs.normalize(root .. '/' .. target)

    add_if_allowed(relative)
    add_if_allowed(rooted)

    if not target:match '%.%w+$' then
      add_if_allowed(relative .. '.md')
      add_if_allowed(relative .. '/index.md')
      add_if_allowed(rooted .. '.md')
      add_if_allowed(rooted .. '/index.md')
    end
  else
    for _, path in ipairs(files) do
      local basename = vim.fn.fnamemodify(path, ':t:r')
      local filename = vim.fn.fnamemodify(path, ':t')
      if basename == target or filename == target then
        matches[path] = true
      end
    end
  end

  local paths = vim.tbl_keys(matches)
  table.sort(paths)
  return paths
end

local function default_note_dir(root, origin)
  local app = read_obsidian_app(root)
  if app and app.newFileLocation == 'folder' and type(app.newFileFolderPath) == 'string' and app.newFileFolderPath ~= '' then
    return vim.fs.normalize(root .. '/' .. app.newFileFolderPath)
  end

  if app and app.newFileLocation == 'current' and origin ~= '' then
    return vim.fs.dirname(origin)
  end

  return root
end

local function new_note_path(root, target, origin)
  local path = nil

  if target:sub(1, 1) == '/' then
    path = vim.fs.normalize(root .. target)
  elseif target:find '/' then
    path = vim.fs.normalize(vim.fs.dirname(origin) .. '/' .. target)
  else
    path = vim.fs.normalize(default_note_dir(root, origin) .. '/' .. target)
  end

  if not path:match '%.%w+$' then
    path = path .. '.md'
  end

  return path
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
    local start_col, end_col = line:find('#[%w][%w_/%-]*', init)
    if not start_col then
      return nil
    end

    if col >= start_col and col <= end_col then
      return line:sub(start_col + 1, end_col)
    end

    init = end_col + 1
  end
end

local function completion_context()
  local path = vim.api.nvim_buf_get_name(0)
  local root = detect_vault_root(path)
  if not root then
    return nil
  end

  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local prefix = line:sub(1, col)

  local note_start = prefix:find('%[%[[^%]]*$')
  if note_start then
    local has_closing = line:sub(col + 1, col + 2) == ']]'
    return {
      kind = 'note',
      root = root,
      start_col = note_start + 1,
      with_closing = not has_closing,
    }
  end

  local tag_start = prefix:find('#[%w_/%-]*$')
  if tag_start then
    local first = prefix:sub(tag_start + 1, tag_start + 1)
    local previous = tag_start > 1 and prefix:sub(tag_start - 1, tag_start - 1) or ''

    if (first == '' or first:match '%w') and (tag_start == 1 or previous:match '[%s%-%(%[]') then
      return {
        kind = 'tag',
        root = root,
        start_col = tag_start,
      }
    end
  end

  return nil
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

local function create_note(path)
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  if not file_exists(path) then
    vim.fn.writefile({}, path)
  end
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

  return note_matches(root, target, origin)
end

local function grep_vault(root, opts)
  require('snacks').picker.grep(vim.tbl_extend('force', {
    cwd = root,
    glob = { '*.md' },
  }, opts or {}))
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
    local path = new_note_path(root, target, origin)
    create_note(path)
    open_note(path, anchor)
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
  grep_vault(root, {
    search = '[[' .. note_name,
    regex = false,
  })
  return true
end

function M.find_tag_references(tag)
  local path = vim.api.nvim_buf_get_name(0)
  local root = detect_vault_root(path)
  local current_tag = tag or parse_tag()

  if not (root and current_tag) then
    return false
  end

  local root_namespace = current_tag:match '^([^/]+)/[^/]+$'
  local pattern = nil

  if root_namespace then
    pattern = ('(^|[^[:alnum:]_/-])#%s(/[[:alnum:]_-]+)?([^[:alnum:]_/-]|$)'):format(escape_regex(root_namespace))
  else
    pattern = ('(^|[^[:alnum:]_/-])#%s([^[:alnum:]_/-]|$)'):format(escape_regex(current_tag))
  end

  grep_vault(root, {
    search = pattern,
    regex = true,
  })
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

  local ok = pcall(vim.cmd, 'normal! gf')
  if not ok then
    vim.notify('No wiki link, tag, or file under cursor', vim.log.levels.WARN)
  end
end

function M.show_references()
  if M.find_tag_references() then
    return
  end

  if M.find_backlinks() then
    return
  end

  vim.notify('No tag or note page to search from', vim.log.levels.WARN)
end

function M.omnifunc(findstart, _)
  local context = completion_context()
  if not context then
    return findstart == 1 and -2 or { words = {} }
  end

  if findstart == 1 then
    return context.start_col
  end

  if context.kind == 'note' then
    return { words = note_completion_items(context.root, context.with_closing) }
  end

  return { words = tag_completion_items(context.root) }
end

local function trigger_completion()
  vim.schedule(function()
    if not vim.startswith(vim.api.nvim_get_mode().mode, 'i') or vim.fn.pumvisible() == 1 then
      return
    end

    vim.api.nvim_feedkeys(vim.keycode '<C-x><C-o>', 'n', false)
  end)
end

function M.insert_open_bracket()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local line = vim.api.nvim_get_current_line()
  local previous = col > 0 and line:sub(col, col) or ''

  if previous == '[' then
    trigger_completion()
  end

  return '['
end

function M.insert_hash()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local line = vim.api.nvim_get_current_line()
  local previous = col > 0 and line:sub(col, col) or ''

  if col == 0 or previous:match '[%s%-%(%[]' then
    trigger_completion()
  end

  return '#'
end

function M.insert_tab()
  return '  '
end

function M.setup()
  local group = vim.api.nvim_create_augroup('nvim-next-markdown-vault', { clear = true })

  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = 'markdown',
    desc = 'Enable note navigation inside Obsidian or Logseq vaults',
    callback = function(event)
      local path = vim.api.nvim_buf_get_name(event.buf)
      if not detect_vault_root(path) then
        return
      end

      vim.bo[event.buf].omnifunc = "v:lua.require'config.markdown_vault'.omnifunc"
      vim.api.nvim_set_option_value('completeopt', 'menuone,popup,noselect', {
        scope = 'local',
        buf = event.buf,
      })

      vim.keymap.set('n', 'gd', M.goto_definition, {
        buffer = event.buf,
        desc = 'Vault: Follow link or tag',
      })
      vim.keymap.set('n', 'gr', M.show_references, {
        buffer = event.buf,
        desc = 'Vault: Search backlinks or tag refs',
      })
      vim.keymap.set('i', '[', M.insert_open_bracket, {
        buffer = event.buf,
        expr = true,
        desc = 'Vault: Trigger note completion',
      })
      vim.keymap.set('i', '#', M.insert_hash, {
        buffer = event.buf,
        expr = true,
        desc = 'Vault: Trigger tag completion',
      })
      vim.keymap.set('i', '<Tab>', M.insert_tab, {
        buffer = event.buf,
        expr = true,
        desc = 'Vault: Insert two spaces',
      })
    end,
  })
end

M._detect_vault_root = detect_vault_root
M._new_note_path = new_note_path

return M
