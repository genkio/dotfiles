return {
  cmd = { 'typescript-language-server', '--stdio' },
  filetypes = {
    'javascript',
    'javascriptreact',
    'typescript',
    'typescriptreact',
  },
  init_options = {
    hostInfo = 'neovim',
  },
  root_dir = function(bufnr, on_dir)
    local root_markers = { 'package-lock.json', 'yarn.lock', 'pnpm-lock.yaml', 'bun.lockb', 'bun.lock' }
    local workspace_markers = { 'pnpm-workspace.yaml' }
    local git_root = vim.fs.root(bufnr, { '.git' })
    local project_root = nil

    if git_root then
      for _, marker in ipairs(vim.list_extend(vim.deepcopy(root_markers), workspace_markers)) do
        if vim.uv.fs_stat(vim.fs.joinpath(git_root, marker)) then
          project_root = git_root
          break
        end
      end
    end

    if not project_root then
      project_root = vim.fs.root(bufnr, { root_markers, { '.git' } })
    end

    local deno_root = vim.fs.root(bufnr, { 'deno.json', 'deno.jsonc' })
    local deno_lock_root = vim.fs.root(bufnr, { 'deno.lock' })

    if deno_lock_root and (not project_root or #deno_lock_root > #project_root) then
      return
    end

    if deno_root and (not project_root or #deno_root >= #project_root) then
      return
    end

    on_dir(project_root or vim.fn.getcwd())
  end,
}
