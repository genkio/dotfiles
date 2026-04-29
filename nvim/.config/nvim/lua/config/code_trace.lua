local M = {}

local TITLE = 'codetrace'

-- Module-level state — survives across floating-window opens/closes so the user
-- can drill into a target and come back to the map via <leader>gs without
-- re-tracing, with their cursor exactly where they left it.
local last = { map = nil, mode = nil, cursor_line = nil }

-- Tracks the currently-open modal so VimResized can redraw it at the new
-- terminal size. Only one modal is ever open at a time.
local active = nil

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = TITLE })
end

-- Defaults; overridable via vim.g.codetrace_*
local function config()
  return {
    agent_cmd        = vim.g.codetrace_agent_cmd or 'codex',
    cache_dir        = vim.fn.stdpath('cache') .. '/codetrace',
    reasoning_local  = vim.g.codetrace_reasoning_local or 'medium',
    reasoning_wide   = vim.g.codetrace_reasoning_wide or 'high',
    timeout_local_ms = vim.g.codetrace_timeout_local_ms or 180000,
    timeout_wide_ms  = vim.g.codetrace_timeout_wide_ms or 600000,
  }
end

local SCHEMA_JSON = [==[
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "CodetraceMap",
  "type": "object",
  "required": ["anchor", "role", "signature", "callers", "effects", "consumers", "warnings"],
  "additionalProperties": false,
  "properties": {
    "anchor": {
      "type": "object",
      "required": ["file", "line", "symbol"],
      "additionalProperties": false,
      "properties": {
        "file":   { "type": "string" },
        "line":   { "type": "integer", "minimum": 1 },
        "symbol": { "type": "string" }
      }
    },
    "role":      { "type": "string" },
    "signature": {
      "type": "object",
      "required": ["in", "out"],
      "additionalProperties": false,
      "properties": {
        "in":  { "type": "string" },
        "out": { "type": "string" }
      }
    },
    "callers": {
      "type": "array", "maxItems": 7,
      "items": {
        "type": "object",
        "required": ["kind", "label", "context", "file", "line"],
        "additionalProperties": false,
        "properties": {
          "kind":    { "type": "string" },
          "label":   { "type": "string" },
          "context": { "type": "string" },
          "file":    { "type": "string" },
          "line":    { "type": "integer", "minimum": 1 }
        }
      }
    },
    "effects": {
      "type": "array", "maxItems": 7,
      "items": {
        "type": "object",
        "required": ["kind", "target", "description", "op"],
        "additionalProperties": false,
        "properties": {
          "kind":        { "type": "string" },
          "target":      { "type": "string" },
          "description": { "type": "string" },
          "op":          { "type": "string" }
        }
      }
    },
    "consumers": {
      "type": "array", "maxItems": 7,
      "items": {
        "type": "object",
        "required": ["name", "via", "purpose", "file", "line"],
        "additionalProperties": false,
        "properties": {
          "name":    { "type": "string" },
          "via":     { "type": "string" },
          "purpose": { "type": "string" },
          "file":    { "type": "string" },
          "line":    { "type": "integer", "minimum": 1 }
        }
      }
    },
    "warnings": {
      "type": "array",
      "items": { "type": "string" }
    }
  }
}
]==]

local PROMPT_LOCAL = [==[
You are mapping the *neighborhood* of a single code symbol in the user's codebase. The goal is **comprehension at a glance** — a high-level map readable in under a minute. This is NOT a sequential trace; it is a spatial map (one screen, all directions).

# Anchor

```
file:    __ANCHOR_FILE__
line:    __ANCHOR_LINE__
symbol:  __ANCHOR_SYMBOL__
```

# Scope

**LOCAL FOCUS — single package only.** Look only inside the package containing the anchor file (e.g. for `packages/foo/src/x.ts`, stay inside `packages/foo/`; for non-monorepo projects, stay inside the nearest enclosing module/app). Do NOT trace into sibling packages. Cross-package callers/consumers belong in a separate "wide" pass; this is the fast daily-driver.

# Task

Discover and synthesize, **inside the anchor's package only**:
- **Callers** — direct invocation sites (max 4)
- **Effects** — side effects: queue emits, DB writes, return, throw, log (max 4)
- **Consumers** — what reads/depends on those effects within the same package (max 4)
- **Role** — 1–2 plain-English sentences on *why this exists*.

Use file-reading and grep tools. Do NOT modify any files.

Be honest about uncertainty in `warnings`.

# Guidelines

- Hard cap: callers ≤ 4, effects ≤ 4, consumers ≤ 4. Pick the most important.
- `role`: 1–2 sentences max. Plain English.
- No cross-package references. If a caller is in another package, mention it once in `warnings`.
- Final assistant message: **only the JSON object** matching the supplied schema. No prose, no fences.
]==]

local PROMPT_WIDE = [==[
You are mapping the *neighborhood* of a single code symbol in the user's codebase. The goal is **comprehension** — the user has blind spots in a large codebase and wants a thorough cross-cutting view. This is NOT a sequential trace; it is a spatial map (one screen, all directions).

# Anchor

```
file:    __ANCHOR_FILE__
line:    __ANCHOR_LINE__
symbol:  __ANCHOR_SYMBOL__
```

# Scope

**WIDE — cross-package allowed.** This is the slow, thorough pass. Trace through monorepo packages, downstream consumers (UI hooks, CLIs, tests), and indirect callers via routes/APIs.

# Task

Discover and synthesize:
- **Callers** — invocation sites across packages (max 7)
- **Effects** — side effects: queue emits, DB writes, return, throw, log (max 7)
- **Consumers** — downstream code that depends on the effects (max 7)
- **Role** — 1–3 plain-English sentences on *why this exists*.

Use file-reading and grep tools. Do NOT modify any files.

Be honest about uncertainty in `warnings`.

# Guidelines

- Hard cap: callers ≤ 7, effects ≤ 7, consumers ≤ 7. Pick the most important.
- `role`: 1–3 sentences max.
- Use whatever framework conventions you discover; adapt rather than impose.
- Final assistant message: **only the JSON object** matching the supplied schema. No prose, no fences.
]==]

local function repo_root(path)
  local result = vim.system({
    'git', '-C', vim.fs.dirname(path), 'rev-parse', '--show-toplevel',
  }, { text = true }):wait()
  if result.code ~= 0 then
    return nil, 'Not in a git worktree'
  end
  return vim.trim(result.stdout or ''), nil
end

local function git_head(root)
  local result = vim.system({
    'git', '-C', root, 'rev-parse', 'HEAD',
  }, { text = true }):wait()
  if result.code ~= 0 then return 'unknown' end
  return vim.trim(result.stdout or 'unknown')
end

local function get_anchor()
  local path = vim.api.nvim_buf_get_name(0)
  if path == '' then
    return nil, 'Current buffer has no file path'
  end
  local pos = vim.api.nvim_win_get_cursor(0)
  local symbol = vim.fn.expand('<cword>')
  if symbol == '' then
    return nil, 'No symbol under cursor'
  end
  return {
    abs_path = vim.fs.normalize(path),
    line     = pos[1],
    symbol   = symbol,
  }, nil
end

local function build_prompt(template, anchor, root)
  local rel = vim.fs.relpath(root, anchor.abs_path) or anchor.abs_path
  return (template
    :gsub('__ANCHOR_FILE__',   vim.pesc(rel))
    :gsub('__ANCHOR_LINE__',   tostring(anchor.line))
    :gsub('__ANCHOR_SYMBOL__', vim.pesc(anchor.symbol)))
end

local function write_file(path, content)
  local f, err = io.open(path, 'w')
  if not f then
    return nil, err
  end
  f:write(content)
  f:close()
  return true
end

local function read_file(path)
  local f = io.open(path, 'r')
  if not f then return nil end
  local content = f:read('*a')
  f:close()
  return content
end

local function wrap(text, width)
  local out, line = {}, ''
  for word in text:gmatch('%S+') do
    if #line == 0 then
      line = word
    elseif #line + 1 + #word <= width then
      line = line .. ' ' .. word
    else
      table.insert(out, line)
      line = word
    end
  end
  if #line > 0 then table.insert(out, line) end
  return out
end

-- Cache key combines git HEAD with anchor identity, so the cache auto-invalidates
-- when commits change the surrounding code. Mode is part of the key because
-- local and wide produce different maps.
local function cache_key(anchor, mode, root)
  local rel = vim.fs.relpath(root, anchor.abs_path) or anchor.abs_path
  local head = git_head(root)
  local raw = string.format('%s|%s|%d|%s|%s', head, rel, anchor.line, anchor.symbol, mode)
  return vim.fn.sha256(raw)
end

local function cache_path(cfg, key)
  return string.format('%s/cache/%s.json', cfg.cache_dir, key)
end

local function cache_load(cfg, key)
  return read_file(cache_path(cfg, key))
end

local function cache_save(cfg, key, content)
  local path = cache_path(cfg, key)
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  write_file(path, content)
end

-- Build display lines + a row→target index for jump/drill.
-- Every line within a caller/consumer block points to the same target. The
-- glyph at the start of each interactive row makes it visible:
--   ▸  starts a new item — header line
--   │  continuation line of the same item — also clickable
-- All descriptive fields wrap to the modal width with proper continuation
-- indent so the modal never produces overflowing lines.
local function build_view(map, width)
  local lines, targets, target_lines = {}, {}, {}
  -- Reserve 2 cols for visual padding; a floor keeps us sane on tiny windows.
  local content_width = math.max(48, width - 2)

  local function add(text, target)
    table.insert(lines, text)
    if target then
      targets[#lines] = target
      table.insert(target_lines, #lines)
    end
  end

  -- Wrap `text` so each line fits within content_width once decorated.
  -- First wrapped line gets `first_prefix`; subsequent lines get `cont_prefix`.
  -- All wrapped lines share `target` (they belong to the same logical item).
  local function add_field(first_prefix, cont_prefix, text, target)
    local first_w = vim.fn.strdisplaywidth(first_prefix)
    local cont_w  = vim.fn.strdisplaywidth(cont_prefix)
    local budget  = math.max(8, content_width - math.max(first_w, cont_w))
    local wrapped = wrap(text or '', budget)
    if #wrapped == 0 then add(first_prefix, target); return end
    for i, l in ipairs(wrapped) do
      add((i == 1 and first_prefix or cont_prefix) .. l, target)
    end
  end

  local anchor_target = { file = map.anchor.file, line = map.anchor.line }
  add(string.format('▸ %s', map.anchor.symbol), anchor_target)
  add(string.format('│ %s:%d', map.anchor.file, map.anchor.line), anchor_target)
  add('')

  add('Role')
  add_field('  ', '  ', map.role, nil)
  add('')

  add('Signature')
  add_field('  in   ', '       ', map.signature['in'] or '?', nil)
  add_field('  out  ', '       ', map.signature.out   or '?', nil)
  add('')

  add(string.format('Called by  (%d)', #map.callers))
  for i, c in ipairs(map.callers) do
    local target = { file = c.file, line = c.line }
    add(string.format('▸ [%s]  %s', c.kind, c.label), target)
    add_field('│   ', '│   ', c.context, target)
    add(string.format('│   %s:%d', c.file, c.line), target)
    if i < #map.callers then add('') end
  end
  add('')

  add(string.format('Effects  (%d)', #map.effects))
  for i, e in ipairs(map.effects) do
    add_field('  [' .. e.kind .. ']  ' .. e.op .. '  →  ', '      ', e.target, nil)
    add_field('    ', '    ', e.description, nil)
    if i < #map.effects then add('') end
  end
  add('')

  add(string.format('Consumers  (%d)', #map.consumers))
  for i, x in ipairs(map.consumers) do
    local target = { file = x.file, line = x.line }
    add_field('▸ ' .. x.name .. '  via  ', '    ', x.via, target)
    add_field('│   ', '│   ', x.purpose, target)
    add(string.format('│   %s:%d', x.file, x.line), target)
    if i < #map.consumers then add('') end
  end

  if map.warnings and #map.warnings > 0 then
    add('')
    add('Warnings')
    for _, w in ipairs(map.warnings) do
      add_field('  - ', '    ', w, nil)
    end
  end

  add('')
  add('  <CR> jump   <Tab>/<S-Tab> next/prev   r/R re-run   q close')

  return lines, targets, target_lines
end

-- Apply syntax highlighting via extmarks. Pure pattern-driven so we don't need
-- a separate syntax/codetrace.vim file — keeps the plugin a single deletable
-- module.
local function apply_highlights(bufnr, ns, lines)
  local function mark(row, col_start, col_end, hl)
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, row, col_start, {
      end_col  = col_end,
      hl_group = hl,
    })
  end

  -- ▸ and │ are 3 bytes each in UTF-8.
  local TRI = '\xE2\x96\xB8'  -- ▸
  local PIPE = '\xE2\x94\x82' -- │
  local ARROW = '\xE2\x86\x92' -- →

  for i, line in ipairs(lines) do
    local row = i - 1

    if line:sub(1, 3) == TRI then
      mark(row, 0, 3, 'Special')
      if row == 0 then
        -- First row is the anchor symbol; bold it as a Function.
        mark(row, 4, #line, 'Function')
      end
    elseif line:sub(1, 3) == PIPE then
      mark(row, 0, 3, 'Comment')
    end

    -- Section headers (whole line)
    if line == 'Role' or line == 'Signature' or line == 'Warnings'
      or line:match('^Called by%s')
      or line:match('^Effects%s')
      or line:match('^Consumers%s') then
      mark(row, 0, #line, 'Title')
    end

    -- [kind] tokens — anything except `]` inside brackets, so multi-word
    -- kinds like [DB read] or [state mutation] get highlighted too.
    do
      local pos = 1
      while true do
        local s, e = line:find('%[[^%]]+%]', pos)
        if not s then break end
        mark(row, s - 1, e, 'Type')
        pos = e + 1
      end
    end

    -- file/path:line patterns — Directory for the path, Number for the line no.
    do
      local pos = 1
      while true do
        local fs, fe = line:find('[%w%-_./]+%.[%w]+:%d+', pos)
        if not fs then break end
        local colon = line:find(':', fs, true)
        if colon and colon < fe then
          mark(row, fs - 1, colon - 1, 'Directory')
          mark(row, colon, fe, 'Number')
        end
        pos = fe + 1
      end
    end

    -- → arrow
    do
      local pos = 1
      while true do
        local s, e = line:find(ARROW, pos, true)
        if not s then break end
        mark(row, s - 1, e, 'Operator')
        pos = e + 1
      end
    end

    -- Footer help line
    if line:match('^%s+<CR>') then
      mark(row, 0, #line, 'Comment')
    end

    -- Warning bullet lines (start with "  - " or are continuations under Warnings)
    if line:match('^  %- ') then
      mark(row, 0, #line, 'WarningMsg')
    end
  end
end

local function jump_to(target)
  if not target then return false end
  vim.cmd(string.format('edit %s', vim.fn.fnameescape(target.file)))
  vim.api.nvim_win_set_cursor(0, { target.line, 0 })
  return true
end

local trace  -- forward declaration so render() can re-run

-- restore_cursor: when true, place the cursor at last.cursor_line if it's still
-- valid for this map. Used by show_last so the user comes back to where they
-- were rather than the top of the modal.
local function render(map, mode, restore_cursor)
  last.map, last.mode = map, mode

  -- Use the full available width of the nvim window (which == tmux pane width)
  -- minus a small padding for the border. No cap — the user wants the modal to
  -- grow with the pane. Wrapping inside build_view handles readability.
  local width  = math.max(48, vim.o.columns - 4)
  local lines, targets, target_lines = build_view(map, width)

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].buftype    = 'nofile'
  vim.bo[bufnr].bufhidden  = 'wipe'
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].filetype   = 'codetrace'

  local height = math.min(#lines + 2, vim.o.lines - 4)
  local row    = math.floor((vim.o.lines - height) / 2)
  local col    = math.floor((vim.o.columns - width) / 2)

  local winid = vim.api.nvim_open_win(bufnr, true, {
    relative  = 'editor',
    width     = width,
    height    = height,
    row       = row,
    col       = col,
    style     = 'minimal',
    border    = 'rounded',
    title     = string.format(' codetrace: %s [%s] ', map.anchor.symbol, mode or 'local'),
    title_pos = 'center',
  })

  -- Register this as the active modal so VimResized can redraw it at the new
  -- terminal size.
  active = { winid = winid, bufnr = bufnr, map = map, mode = mode }

  vim.wo[winid].cursorline    = true
  vim.wo[winid].cursorlineopt = 'both'
  vim.wo[winid].wrap          = false

  local ns = vim.api.nvim_create_namespace('codetrace_marks')
  apply_highlights(bufnr, ns, lines)

  -- Initial cursor placement: prefer restoring user's last position; else land
  -- on the first interactive row.
  local function place_initial_cursor()
    if restore_cursor and last.cursor_line and last.cursor_line >= 1 and last.cursor_line <= #lines then
      vim.api.nvim_win_set_cursor(winid, { last.cursor_line, 0 })
      return
    end
    if target_lines[1] then
      vim.api.nvim_win_set_cursor(winid, { target_lines[1], 0 })
    end
  end
  place_initial_cursor()

  local function save_cursor()
    if vim.api.nvim_win_is_valid(winid) then
      last.cursor_line = vim.api.nvim_win_get_cursor(winid)[1]
    end
  end

  local function close()
    save_cursor()
    if winid and vim.api.nvim_win_is_valid(winid) then
      vim.api.nvim_win_close(winid, true)
    end
    if active and active.winid == winid then active = nil end
  end

  local function target_at_cursor()
    return targets[vim.api.nvim_win_get_cursor(0)[1]]
  end

  local function goto_next()
    local cur = vim.api.nvim_win_get_cursor(0)[1]
    for _, l in ipairs(target_lines) do
      if l > cur then
        vim.api.nvim_win_set_cursor(winid, { l, 0 })
        return
      end
    end
    if target_lines[1] then vim.api.nvim_win_set_cursor(winid, { target_lines[1], 0 }) end
  end

  local function goto_prev()
    local cur = vim.api.nvim_win_get_cursor(0)[1]
    for i = #target_lines, 1, -1 do
      if target_lines[i] < cur then
        vim.api.nvim_win_set_cursor(winid, { target_lines[i], 0 })
        return
      end
    end
    if target_lines[#target_lines] then
      vim.api.nvim_win_set_cursor(winid, { target_lines[#target_lines], 0 })
    end
  end

  local function jump_under_cursor()
    local t = target_at_cursor()
    if not t then notify('Cursor not on a jump target', vim.log.levels.WARN); return end
    close()
    jump_to(t)
  end

  local opts = { buffer = bufnr, nowait = true }
  local function set(key, fn, desc)
    vim.keymap.set('n', key, fn, vim.tbl_extend('force', opts, { desc = 'codetrace: ' .. desc }))
  end

  set('q',       close,             'close')
  set('<Esc>',   close,             'close')
  set('<CR>',    jump_under_cursor, 'jump')
  set('<Tab>',   goto_next,         'next target')
  set('<S-Tab>', goto_prev,         'prev target')

  set('r', function()
    -- Re-run forces fresh; cursor restoration doesn't apply since we get a new
    -- map. Don't call save_cursor because the new map starts the user fresh.
    if vim.api.nvim_win_is_valid(winid) then vim.api.nvim_win_close(winid, true) end
    if jump_to({ file = map.anchor.file, line = map.anchor.line }) then trace('local', true) end
  end, 're-run (force fresh)')

  set('R', function()
    if vim.api.nvim_win_is_valid(winid) then vim.api.nvim_win_close(winid, true) end
    if jump_to({ file = map.anchor.file, line = map.anchor.line }) then trace('wide', true) end
  end, 're-run wide (force fresh)')
end

trace = function(mode, force_fresh)
  local cfg = config()
  if vim.fn.executable(cfg.agent_cmd) ~= 1 then
    notify(string.format('Agent CLI not found on PATH: %s', cfg.agent_cmd), vim.log.levels.ERROR)
    return
  end

  local anchor, anchor_err = get_anchor()
  if not anchor then notify(anchor_err, vim.log.levels.WARN); return end

  local root, root_err = repo_root(anchor.abs_path)
  if not root then notify(root_err, vim.log.levels.WARN); return end

  vim.fn.mkdir(cfg.cache_dir, 'p')
  local key = cache_key(anchor, mode, root)

  if not force_fresh then
    local cached = cache_load(cfg, key)
    if cached then
      local ok_d, decoded = pcall(vim.json.decode, cached)
      if ok_d and type(decoded) == 'table' then
        notify(string.format('cache hit  %s [%s]', anchor.symbol, mode))
        -- Fresh trace: clear any previously-saved cursor since this is a new
        -- modal context.
        last.cursor_line = nil
        render(decoded, mode)
        return
      end
    end
  end

  local stamp       = string.format('%d-%s', os.time(), anchor.symbol:gsub('%W', '_'))
  local schema_path = cfg.cache_dir .. '/schema.json'
  local map_path    = string.format('%s/map-%s.json', cfg.cache_dir, stamp)
  local prompt_path = string.format('%s/prompt-%s.md', cfg.cache_dir, stamp)

  local ok, err = write_file(schema_path, SCHEMA_JSON)
  if not ok then notify('Failed to write schema: ' .. err, vim.log.levels.ERROR); return end

  local template = (mode == 'wide') and PROMPT_WIDE or PROMPT_LOCAL
  local prompt   = build_prompt(template, anchor, root)
  ok, err = write_file(prompt_path, prompt)
  if not ok then notify('Failed to write prompt: ' .. err, vim.log.levels.ERROR); return end

  local reasoning = (mode == 'wide') and cfg.reasoning_wide or cfg.reasoning_local
  local timeout   = (mode == 'wide') and cfg.timeout_wide_ms or cfg.timeout_local_ms

  local cmd = {
    cfg.agent_cmd, 'exec',
    '--cd',                  root,
    '--sandbox',             'read-only',
    '--skip-git-repo-check',
    '-c',                    'model_reasoning_effort=' .. reasoning,
    '--output-schema',       schema_path,
    '--output-last-message', map_path,
    prompt,
  }

  notify(string.format('tracing %s [%s]…', anchor.symbol, mode))
  local started_at = vim.uv.hrtime()

  -- jobstart with pty=true allocates a real pty for the child process. Required
  -- because codex 0.124.0+ silently exits with empty output when stdio is
  -- detached from a TTY (openai/codex#19945).
  local timer
  local job_id = vim.fn.jobstart(cmd, {
    pty     = true,
    on_exit = function(_, code)
      if timer then pcall(vim.uv.timer_stop, timer); pcall(vim.uv.close, timer); timer = nil end
      vim.schedule(function()
        local elapsed_s = (vim.uv.hrtime() - started_at) / 1e9
        if code ~= 0 then
          notify(string.format('agent exited %d after %.0fs', code, elapsed_s), vim.log.levels.ERROR)
          return
        end
        local content = read_file(map_path)
        if not content or content == '' then
          notify('agent produced no output (TTY/codex bug? check ' .. map_path .. ')', vim.log.levels.ERROR)
          return
        end
        local ok_decode, decoded = pcall(vim.json.decode, content)
        if not ok_decode or type(decoded) ~= 'table' then
          notify('failed to parse map JSON at ' .. map_path, vim.log.levels.ERROR)
          return
        end
        cache_save(cfg, key, content)
        notify(string.format('mapped %s in %.0fs', anchor.symbol, elapsed_s))
        last.cursor_line = nil
        render(decoded, mode)
      end)
    end,
  })

  if job_id <= 0 then
    notify('Failed to spawn agent', vim.log.levels.ERROR)
    return
  end

  timer = vim.uv.new_timer()
  timer:start(timeout, 0, vim.schedule_wrap(function()
    pcall(vim.fn.jobstop, job_id)
    notify(string.format('agent timed out after %.0fs', timeout / 1000), vim.log.levels.WARN)
  end))
end

local function show_last()
  if not last.map then
    notify('no previous map — run <leader>gt first', vim.log.levels.WARN)
    return
  end
  render(last.map, last.mode or 'local', true)
end

local function clear_cache()
  local cfg = config()
  local dir = cfg.cache_dir .. '/cache'
  if vim.fn.isdirectory(dir) == 1 then
    vim.fn.delete(dir, 'rf')
    notify('cache cleared')
  else
    notify('cache already empty')
  end
end

function M.trace_local() trace('local') end
function M.trace_wide()  trace('wide')  end
function M.show_last()   show_last()    end
function M.clear_cache() clear_cache()  end

function M.setup()
  vim.keymap.set('n', '<leader>gt', M.trace_local, { desc = 'codetrace: map symbol (local)' })
  vim.keymap.set('n', '<leader>gT', M.trace_wide,  { desc = 'codetrace: map symbol (wide)'  })
  vim.keymap.set('n', '<leader>gs', M.show_last,   { desc = 'codetrace: show last map'      })

  vim.api.nvim_create_user_command('CodeTrace',          function() trace('local')        end, {})
  vim.api.nvim_create_user_command('CodeTraceWide',      function() trace('wide')         end, {})
  vim.api.nvim_create_user_command('CodeTraceForce',     function() trace('local', true)  end, {})
  vim.api.nvim_create_user_command('CodeTraceShow',      function() show_last()           end, {})
  vim.api.nvim_create_user_command('CodeTraceClearCache', function() clear_cache()         end, {})

  -- When the underlying nvim window resizes (tmux pane resize, terminal
  -- resize, zoom toggle, etc.), redraw the active modal at the new size so
  -- the wrap budget and frame match the available space. Cursor position is
  -- preserved across the redraw via the same restore_cursor path that
  -- <leader>gs uses.
  vim.api.nvim_create_autocmd('VimResized', {
    group    = vim.api.nvim_create_augroup('codetrace_resize', { clear = true }),
    callback = function()
      if not active or not active.winid or not vim.api.nvim_win_is_valid(active.winid) then
        return
      end
      last.cursor_line = vim.api.nvim_win_get_cursor(active.winid)[1]
      local map, mode = active.map, active.mode
      pcall(vim.api.nvim_win_close, active.winid, true)
      active = nil
      render(map, mode, true)
    end,
  })
end

return M
