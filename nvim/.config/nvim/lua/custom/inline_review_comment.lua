local M = {}

local state = {
  mode = 'comment',
  context = nil,
  float_buf = nil,
  float_win = nil,
}

local function close_float()
  if state.float_win and vim.api.nvim_win_is_valid(state.float_win) then
    vim.api.nvim_win_close(state.float_win, true)
  end
  if state.float_buf and vim.api.nvim_buf_is_valid(state.float_buf) then
    vim.api.nvim_buf_delete(state.float_buf, { force = true })
  end
  state.float_buf = nil
  state.float_win = nil
  state.mode = 'comment'
  state.context = nil
end

local function trim_lines(lines)
  while #lines > 0 and vim.trim(lines[1]) == '' do
    table.remove(lines, 1)
  end
  while #lines > 0 and vim.trim(lines[#lines]) == '' do
    table.remove(lines)
  end
  return lines
end

local function line_in_unchanged_fold(file, line)
  if not (file and file.custom_folds and file.custom_folds.type == 'diff_patch') then
    return false
  end

  for _, fold in ipairs(file.custom_folds) do
    if line >= fold[1] and line <= fold[2] then
      return true
    end
  end

  return false
end

local function run_gh(args, input)
  local cmd = { 'gh' }
  vim.list_extend(cmd, args)

  local result = vim.system(cmd, {
    text = true,
    stdin = input,
  }):wait()

  if result.code ~= 0 then
    local err = vim.trim(result.stderr or '')
    if err == '' then
      err = 'gh command failed'
    end
    return nil, err, result.stdout
  end

  return result.stdout, nil, result.stderr
end

local function run_gh_json(args, input)
  local output, err, extra = run_gh(args, input)
  if not output then
    return nil, err, extra
  end

  local ok, decoded = pcall(vim.json.decode, output)
  if not ok then
    return nil, 'Failed to decode gh JSON response', output
  end

  return decoded, nil, extra
end

local function repo_from_pr_url(url)
  return url and url:match('github%.com/([^/]+/[^/]+)/pull/%d+')
end

local function split_repo(repo)
  if not repo then
    return nil, nil
  end
  return repo:match '^(.-)/(.-)$'
end

local function run_gh_graphql(query, variables)
  local args = { 'api', 'graphql', '--raw-field', 'query=' .. query }
  for key, value in pairs(variables or {}) do
    if value ~= nil then
      local flag = (type(value) == 'number' or type(value) == 'boolean') and '--field' or '--raw-field'
      table.insert(args, flag)
      table.insert(args, string.format('%s=%s', key, tostring(value)))
    end
  end
  return run_gh_json(args)
end

local function get_diffview_context(from_visual)
  local ok_lib, lib = pcall(require, 'diffview.lib')
  if not ok_lib then
    return nil, 'Diffview is not available'
  end

  local view = lib.get_current_view()
  local layout = view and view.cur_layout or nil
  local entry = view and view.cur_entry or nil
  if not (view and layout and entry) then
    return nil, 'Not in an active Diffview review'
  end

  local current_win = vim.api.nvim_get_current_win()
  local current_buf = vim.api.nvim_get_current_buf()
  local target = nil
  for _, symbol in ipairs { 'a', 'b', 'c', 'd' } do
    local win = layout[symbol]
    if win and win.file and win.file.bufnr == current_buf then
      target = win
      break
    end
  end

  if not (target and target.file) then
    return nil, 'Place cursor in a Diffview code pane'
  end

  local file = target.file
  local side = file.rev and file.rev.type == 1 and 'RIGHT' or 'LEFT'
  local start_line, end_line

  if from_visual or vim.fn.mode():find '^[vV\22]' then
    local from = vim.fn.line "'<"
    local to = vim.fn.line "'>"
    start_line = math.min(from, to)
    end_line = math.max(from, to)
  else
    start_line = vim.api.nvim_win_get_cursor(current_win)[1]
    end_line = start_line
  end

  for line = start_line, end_line do
    if line_in_unchanged_fold(file, line) then
      return nil, 'Select lines that are part of the diff hunk'
    end
  end

  return {
    path = entry.path,
    absolute_path = entry.absolute_path,
    side = side,
    line = end_line,
    start_line = start_line ~= end_line and start_line or nil,
    range_start = start_line,
    range_end = end_line,
    code_lines = vim.api.nvim_buf_get_lines(current_buf, start_line - 1, end_line, false),
  }
end

local function get_current_pr()
  local pr, err = run_gh_json({
    'pr',
    'view',
    '--json',
    'number,headRefOid,url',
  })
  if not pr then
    return nil, err or 'Could not find a current PR for this branch'
  end

  pr.repo = repo_from_pr_url(pr.url)
  if not (pr and pr.repo and pr.number and pr.headRefOid) then
    return nil, 'Could not find a current PR for this branch'
  end

  return pr
end

local function get_pending_review_id(pr)
  local owner, name = split_repo(pr.repo)
  if not (owner and name) then
    return nil, 'Could not parse PR repository'
  end

  local data, err = run_gh_graphql([[
    query($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) {
        pullRequest(number: $number) {
          reviews(first: 100) {
            nodes {
              id
              state
              viewerDidAuthor
            }
          }
        }
      }
    }
  ]], {
    owner = owner,
    name = name,
    number = pr.number,
  })
  if not data then
    return nil, err
  end

  local reviews = vim.tbl_get(data, 'data', 'repository', 'pullRequest', 'reviews', 'nodes') or {}
  for _, review in ipairs(reviews) do
    if review.state == 'PENDING' and review.viewerDidAuthor then
      return review.id
    end
  end
end

local function show_debug_failure(title, sections)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].filetype = 'markdown'

  local lines = { '# ' .. title, '' }
  for _, section in ipairs(sections) do
    lines[#lines + 1] = '## ' .. section.title
    lines[#lines + 1] = '```'
    for _, line in ipairs(vim.split(section.body, '\n', { plain = true })) do
      lines[#lines + 1] = line
    end
    lines[#lines + 1] = '```'
    lines[#lines + 1] = ''
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.cmd 'tabnew'
  vim.api.nvim_win_set_buf(0, buf)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = 'wipe'
  vim.notify('Opened inline review debug tab with full gh error details', vim.log.levels.ERROR)
end

local function get_message_body()
  if not (state.float_buf and vim.api.nvim_buf_is_valid(state.float_buf)) then
    return nil, 'No review comment in progress'
  end

  local lines = vim.api.nvim_buf_get_lines(state.float_buf, 0, -1, false)
  lines = trim_lines(lines)
  if #lines == 0 then
    return nil, 'Comment is empty'
  end

  return table.concat(lines, '\n')
end

local function pr_diff_candidates(pr, path)
  local diff, err = run_gh({
    'pr',
    'diff',
    tostring(pr.number),
    '--repo',
    pr.repo,
  })
  if not diff then
    return nil, err
  end

  local DiffSource = require 'snacks.picker.source.diff'
  local DiffUtil = require 'snacks.picker.util.diff'
  local parsed = DiffSource.parse(vim.split(diff, '\n', { plain = true }))
  local candidates = {}

  for _, block in ipairs(parsed.blocks or {}) do
    if block.file == path then
      local position = 0
      for hunk_index, hunk in ipairs(block.hunks or {}) do
        local hunk_parse = DiffUtil.parse_hunk({ block = block, hunk = hunk })
        local index = DiffUtil.build_hunk_index(hunk_parse)
        if hunk_index > 1 then
          position = position + 1
        end

        for l = 1, hunk_parse.len do
          position = position + 1
          local have_left = index[l][1] ~= nil
          local have_right = index[l][#hunk_parse.versions] ~= nil
          if have_left or have_right then
            table.insert(candidates, {
              side = have_right and 'RIGHT' or 'LEFT',
              line = have_right and index[l][#hunk_parse.versions] or index[l][1],
              code = hunk_parse.lines[l],
              position = position,
            })
          end
        end
      end
    end
  end

  return candidates
end

local function find_pr_diff_line(candidates, line, preferred_side)
  local fallback = nil
  for _, candidate in ipairs(candidates) do
    if candidate.line == line then
      if candidate.side == preferred_side then
        return candidate
      end
      fallback = fallback or candidate
    end
  end

  return fallback
end

local function match_single_line(candidates, context)
  local code = (context.code_lines or {})[1]
  local matches = {}

  for _, candidate in ipairs(candidates) do
    if candidate.code == code then
      table.insert(matches, candidate)
    end
  end

  if #matches == 0 then
    return find_pr_diff_line(candidates, context.line, context.side)
  end

  local exact = nil
  local preferred = nil
  for _, candidate in ipairs(matches) do
    if candidate.line == context.line and candidate.side == context.side then
      exact = candidate
      break
    end
    if not preferred and candidate.side == context.side then
      preferred = candidate
    end
  end

  return exact or preferred or matches[1]
end

local function match_range(candidates, context)
  local code_lines = context.code_lines or {}
  if #code_lines == 0 then
    return nil
  end

  local matches = {}
  for i = 1, #candidates - #code_lines + 1 do
    local ok = true
    for j = 1, #code_lines do
      if candidates[i + j - 1].code ~= code_lines[j] then
        ok = false
        break
      end
    end
    if ok then
      table.insert(matches, {
        first = candidates[i],
        last = candidates[i + #code_lines - 1],
      })
    end
  end

  if #matches == 0 then
    return nil
  end

  for _, match in ipairs(matches) do
    if match.last.side == context.side then
      return match
    end
  end

  return matches[1]
end

local function map_context_to_pr_diff(pr, context)
  local candidates, err = pr_diff_candidates(pr, context.path)
  if not candidates then
    return nil, err
  end

  local effective_context = {
    line = context.line,
    side = context.side,
    code_lines = { (context.code_lines or {})[#(context.code_lines or {})] or '' },
  }

  local final_line = match_single_line(candidates, effective_context)
  if not final_line then
    return nil, 'Selected line is not part of the current GitHub PR diff'
  end

  return {
    path = context.path,
    side = final_line.side,
    line = final_line.line,
    position = final_line.position,
  }
end

local function submit_comment()
  if not (state.float_buf and vim.api.nvim_buf_is_valid(state.float_buf) and state.context) then
    vim.notify('No review comment in progress', vim.log.levels.ERROR)
    return
  end

  local body, body_err = get_message_body()
  if not body then
    vim.notify(body_err, vim.log.levels.WARN)
    return
  end
  vim.fn.setreg('+', body)

  local pr, err = get_current_pr()
  if not pr then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end

  local review_line, map_err = map_context_to_pr_diff(pr, state.context)
  if not review_line then
    vim.notify(map_err, vim.log.levels.ERROR)
    return
  end

  local input = {
    body = body,
    commit_id = pr.headRefOid,
    path = review_line.path,
    side = review_line.side,
    line = review_line.line,
  }

  local pending_review_id, pending_err = get_pending_review_id(pr)
  local result, request_err, request_extra

  if pending_err then
    request_err = pending_err
  elseif pending_review_id then
    request_err = 'A pending review already exists on this PR. Submit or discard it first to add a standalone inline comment.'
  else
    result, request_err, request_extra = run_gh_json({
      'api',
      ('/repos/%s/pulls/%d/comments'):format(pr.repo, pr.number),
      '--method',
      'POST',
      '--input',
      '-',
    }, vim.json.encode(input))
  end

  if not result and review_line.position then
    local fallback_input = {
      body = input.body,
      commit_id = input.commit_id,
      path = input.path,
      position = review_line.position,
    }

    result, request_err, request_extra = run_gh_json({
      'api',
      ('/repos/%s/pulls/%d/comments'):format(pr.repo, pr.number),
      '--method',
      'POST',
      '--input',
      '-',
    }, vim.json.encode(fallback_input))
  end

  if not result then
    show_debug_failure('Inline Review Comment Failed', {
      {
        title = 'PR',
        body = vim.inspect(pr),
      },
      {
        title = 'Context',
        body = vim.inspect(state.context),
      },
      {
        title = 'Mapped Review Line',
        body = vim.inspect(review_line),
      },
      {
        title = 'Pending Review ID',
        body = vim.inspect(pending_review_id),
      },
      {
        title = 'Payload',
        body = vim.json.encode(input),
      },
      {
        title = 'gh api Error',
        body = (request_err or 'unknown error') .. (request_extra and ('\n\n' .. request_extra) or ''),
      },
    })
    vim.notify((request_err or 'Failed to create review comment') .. ' (see opened debug tab)', vim.log.levels.ERROR)
    return
  end

  close_float()
  vim.notify(('Added review comment to PR #%d'):format(pr.number), vim.log.levels.INFO)
end

local function submit_approve()
  if not state.float_buf or not vim.api.nvim_buf_is_valid(state.float_buf) then
    vim.notify('No review comment in progress', vim.log.levels.ERROR)
    return
  end

  local body, body_err = get_message_body()
  if not body then
    vim.notify(body_err, vim.log.levels.WARN)
    return
  end
  vim.fn.setreg('+', body)

  local pr, err = get_current_pr()
  if not pr then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end

  local pending_review_id, pending_err = get_pending_review_id(pr)
  if pending_err then
    vim.notify(pending_err, vim.log.levels.ERROR)
    return
  end

  if pending_review_id then
    vim.notify('A pending review already exists on this PR. Submit or discard it first before approving here.', vim.log.levels.WARN)
    return
  end

  local input = {
    body = body,
    event = 'APPROVE',
    commit_id = pr.headRefOid,
  }

  local result, request_err, request_extra = run_gh_json({
    'api',
    ('/repos/%s/pulls/%d/reviews'):format(pr.repo, pr.number),
    '--method',
    'POST',
    '--input',
    '-',
  }, vim.json.encode(input))

  if not result then
    show_debug_failure('Approve Review Failed', {
      {
        title = 'PR',
        body = vim.inspect(pr),
      },
      {
        title = 'Payload',
        body = vim.json.encode(input),
      },
      {
        title = 'gh api Error',
        body = (request_err or 'unknown error') .. (request_extra and ('\n\n' .. request_extra) or ''),
      },
    })
    vim.notify((request_err or 'Failed to approve PR') .. ' (see opened debug tab)', vim.log.levels.ERROR)
    return
  end

  close_float()
  vim.notify(('Approved PR #%d'):format(pr.number), vim.log.levels.INFO)
end

function M.open(from_visual, mode)
  local context, err = get_diffview_context(from_visual)
  if not context then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end

  local pr, pr_err = get_current_pr()
  if not pr then
    vim.notify(pr_err, vim.log.levels.ERROR)
    return
  end

  close_float()

  local float_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[float_buf].buftype = 'nofile'
  vim.bo[float_buf].filetype = 'markdown'

  local width = math.floor(vim.o.columns * 0.6)
  local height = math.max(math.floor(vim.o.lines * 0.25), 5)
  local short_name = vim.fn.fnamemodify(context.absolute_path, ':t')
  local title = string.format(
    ' %s: PR #%d %s:%d-%d ',
    mode == 'approve' and 'Approve Review' or 'Review Comment',
    pr.number,
    short_name,
    context.range_start,
    context.range_end
  )

  local float_win = vim.api.nvim_open_win(float_buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = 'minimal',
    border = 'rounded',
    title = title,
    title_pos = 'center',
  })

  state.mode = mode or 'comment'
  state.context = context
  state.float_buf = float_buf
  state.float_win = float_win

  local submit_primary = state.mode == 'approve' and submit_approve or submit_comment
  vim.keymap.set('n', '<leader>is', submit_comment, { buffer = float_buf, desc = 'Review comment: submit' })
  vim.keymap.set('n', '<leader>ia', submit_approve, { buffer = float_buf, desc = 'Review comment: approve PR' })
  vim.keymap.set('n', '<C-s>', submit_primary, { buffer = float_buf, desc = 'Review comment: primary submit' })
  vim.keymap.set('n', '<leader>iq', close_float, { buffer = float_buf, desc = 'Review comment: cancel' })

  vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, { '' })
  vim.api.nvim_win_set_cursor(float_win, { 1, 0 })
  vim.cmd 'startinsert!'
end

return M
