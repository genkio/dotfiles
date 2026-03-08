local M = {}

local state = ya.sync(function()
  local selected = {}
  for _, url in pairs(cx.active.selected) do
    selected[#selected + 1] = url
  end
  return cx.active.current.cwd, selected
end)

local function git_root(cwd)
  local child, err = Command("git")
    :arg("rev-parse")
    :arg("--show-toplevel")
    :cwd(tostring(cwd))
    :stdout(Command.PIPED)
    :stderr(Command.NULL)
    :spawn()

  if not child then
    return cwd, err
  end

  local output, wait_err = child:wait_with_output()
  if not output or not output.status.success then
    return cwd, wait_err
  end

  local root = output.stdout:gsub("[\r\n]+$", "")
  if root == "" then
    return cwd, nil
  end

  return Url(root), nil
end

function M:entry()
  ya.emit("escape", { visual = true })

  local cwd, selected = state()
  if cwd.scheme.is_virtual then
    return ya.notify {
      title = "Project Fzf",
      content = "Not supported under virtual filesystems",
      timeout = 5,
      level = "warn",
    }
  end

  local search_root = cwd
  if #selected == 0 then
    search_root = git_root(cwd)
  end

  local permit = ui.hide()
  local output, err = M.run_with(search_root, selected)
  permit:drop()

  if not output then
    return ya.notify {
      title = "Project Fzf",
      content = tostring(err),
      timeout = 5,
      level = "error",
    }
  end

  local urls = M.split_urls(search_root, output)
  if #urls == 1 then
    local cha = #selected == 0 and fs.cha(urls[1])
    ya.emit(cha and cha.is_dir and "cd" or "reveal", { urls[1], raw = true })
  elseif #urls > 1 then
    urls.state = #selected > 0 and "off" or "on"
    ya.emit("toggle_all", urls)
  end
end

---@param cwd Url
---@param selected Url[]
---@return string?, Error?
function M.run_with(cwd, selected)
  local child, err = Command("fzf")
    :arg("-m")
    :cwd(tostring(cwd))
    :stdin(#selected > 0 and Command.PIPED or Command.INHERIT)
    :stdout(Command.PIPED)
    :spawn()

  if not child then
    return nil, Err("Failed to start `fzf`, error: %s", err)
  end

  for _, url in ipairs(selected) do
    child:write_all(string.format("%s\n", url))
  end
  if #selected > 0 then
    child:flush()
  end

  local output, wait_err = child:wait_with_output()
  if not output then
    return nil, Err("Cannot read `fzf` output, error: %s", wait_err)
  elseif not output.status.success and output.status.code ~= 130 then
    return nil, Err("`fzf` exited with error code %s", output.status.code)
  end

  return output.stdout, nil
end

function M.split_urls(cwd, output)
  local urls = {}
  for line in output:gmatch("[^\r\n]+") do
    local url = Url(line)
    if url.is_absolute then
      urls[#urls + 1] = url
    else
      urls[#urls + 1] = cwd:join(url)
    end
  end
  return urls
end

return M
