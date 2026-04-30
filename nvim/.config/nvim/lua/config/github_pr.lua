-- Open the GitHub pull request associated with the current line.
--
-- The flow is intentionally local-first: use git blame to identify the commit,
-- ask gh for the repository and associated PRs, rank likely matches, then open
-- the best PR in the browser or picker. This keeps the keymap lightweight while
-- still handling merged, open, and cross-repository PR metadata.

local M = {}

local TITLE = 'GitHub PR'

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = TITLE })
end

local function run(cmd, opts)
  opts = vim.tbl_extend('force', { text = true }, opts or {})

  local ok, system = pcall(vim.system, cmd, opts)
  if not ok then
    return nil, system
  end

  local result = system:wait()
  if result.code ~= 0 then
    local err = vim.trim(result.stderr or '')
    if err == '' then
      err = vim.trim(result.stdout or '')
    end
    if err == '' then
      err = table.concat(cmd, ' ') .. ' failed'
    end
    return nil, err
  end

  return result.stdout or '', nil
end

local function run_json(cmd, opts)
  local output, err = run(cmd, opts)
  if not output then
    return nil, err
  end

  local ok, decoded = pcall(vim.json.decode, output)
  if not ok then
    return nil, 'Failed to decode JSON response'
  end

  if decoded.errors and decoded.errors[1] and decoded.errors[1].message then
    return nil, decoded.errors[1].message
  end

  return decoded, nil
end

local function current_file_path()
  local path = vim.api.nvim_buf_get_name(0)
  if path == '' then
    return nil, 'Current buffer has no file path'
  end

  return vim.fs.normalize(path)
end

local function repo_root(path)
  local output = run({
    'git',
    '-C',
    vim.fs.dirname(path),
    'rev-parse',
    '--show-toplevel',
  })
  if not output then
    return nil, 'Current file is not in a git worktree'
  end

  return vim.trim(output)
end

local function blamed_commit(root, path, line)
  local relative_path = vim.fs.relpath(root, path) or path
  local output, err = run({
    'git',
    '-C',
    root,
    'blame',
    '--porcelain',
    '-L',
    string.format('%d,+1', line),
    '--',
    relative_path,
  })
  if not output then
    return nil, err or 'Could not blame current line'
  end

  local sha = output:match('^(%w+) ')
  if not sha then
    return nil, 'Could not parse blame output'
  end

  if sha:match '^0+$' then
    return nil, 'Current line is not committed yet'
  end

  return sha
end

local function repo_name_with_owner(root)
  local data, err = run_json({
    'gh',
    'repo',
    'view',
    '--json',
    'nameWithOwner',
  }, {
    cwd = root,
  })
  if not data then
    return nil, err or 'Could not resolve GitHub repo with gh'
  end

  return data.nameWithOwner
end

local QUERY = [[
query($owner: String!, $name: String!, $oid: GitObjectID!) {
  repository(owner: $owner, name: $name) {
    object(oid: $oid) {
      ... on Commit {
        associatedPullRequests(first: 10) {
          nodes {
            number
            title
            url
            state
            mergedAt
            isDraft
          }
        }
      }
    }
  }
}
]]

local function associated_pull_requests(root, sha)
  local name_with_owner, repo_err = repo_name_with_owner(root)
  if not name_with_owner then
    return nil, repo_err
  end

  local owner, name = name_with_owner:match '^(.-)/(.-)$'
  if not (owner and name) then
    return nil, 'Could not parse GitHub repo name'
  end

  local data, err = run_json({
    'gh',
    'api',
    'graphql',
    '--raw-field',
    'query=' .. QUERY,
    '--raw-field',
    'owner=' .. owner,
    '--raw-field',
    'name=' .. name,
    '--raw-field',
    'oid=' .. sha,
  }, {
    cwd = root,
  })
  if not data then
    return nil, err
  end

  local prs = vim.tbl_get(data, 'data', 'repository', 'object', 'associatedPullRequests', 'nodes') or {}
  if #prs == 0 then
    return nil, ('No GitHub PR is associated with commit %s'):format(sha:sub(1, 8))
  end

  return prs
end

local function pr_rank(pr)
  local rank = 0

  if pr.mergedAt then
    rank = rank + 4
  end
  if pr.state == 'MERGED' then
    rank = rank + 2
  end
  if not pr.isDraft then
    rank = rank + 1
  end

  return rank
end

local function sort_pull_requests(prs)
  table.sort(prs, function(a, b)
    local rank_a = pr_rank(a)
    local rank_b = pr_rank(b)
    if rank_a ~= rank_b then
      return rank_a > rank_b
    end

    if a.mergedAt ~= b.mergedAt then
      return (a.mergedAt or '') > (b.mergedAt or '')
    end

    return (a.number or 0) > (b.number or 0)
  end)
end

local function open_pull_request(pr)
  local _, err = vim.ui.open(pr.url)
  if err then
    notify('Failed to open PR URL: ' .. err, vim.log.levels.ERROR)
    return
  end

  notify(('Opened PR #%d'):format(pr.number))
end

local function format_pull_request(pr)
  return ('#%d %s'):format(pr.number, pr.title)
end

function M.open_current_line_pr()
  local path, path_err = current_file_path()
  if not path then
    notify(path_err, vim.log.levels.WARN)
    return
  end

  local root, root_err = repo_root(path)
  if not root then
    notify(root_err, vim.log.levels.WARN)
    return
  end

  local line = vim.api.nvim_win_get_cursor(0)[1]
  local sha, blame_err = blamed_commit(root, path, line)
  if not sha then
    notify(blame_err, vim.log.levels.WARN)
    return
  end

  local prs, pr_err = associated_pull_requests(root, sha)
  if not prs then
    notify(pr_err, vim.log.levels.WARN)
    return
  end

  sort_pull_requests(prs)

  if #prs == 1 then
    open_pull_request(prs[1])
    return
  end

  vim.ui.select(prs, {
    prompt = 'Open PR for blamed line:',
    format_item = format_pull_request,
  }, function(choice)
    if choice then
      open_pull_request(choice)
    end
  end)
end

return M
