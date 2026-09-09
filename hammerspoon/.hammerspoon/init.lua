local function parentDirectory(path)
  return path:match("^(.*)/[^/]+$")
end

local function addLuaSearchPath(directory)
  local patterns = {
    directory .. "/?.lua",
    directory .. "/?/init.lua",
  }

  for _, pattern in ipairs(patterns) do
    if not package.path:find(pattern, 1, true) then
      package.path = pattern .. ";" .. package.path
    end
  end
end

local function initDirectories()
  local directories = { hs.configdir }
  local source = debug.getinfo(1, "S").source

  if type(source) == "string" and source:sub(1, 1) == "@" then
    local initPath = source:sub(2)
    local resolvedPath = hs.fs.pathToAbsolute(initPath)

    table.insert(directories, parentDirectory(initPath))

    if resolvedPath and resolvedPath ~= initPath then
      table.insert(directories, parentDirectory(resolvedPath))
    end
  end

  return directories
end

for _, directory in ipairs(initDirectories()) do
  addLuaSearchPath(directory)
end

local function reloadOnLuaChange(paths)
  for _, path in ipairs(paths) do
    if path:sub(-4) == ".lua" then
      return hs.reload()
    end
  end
end

-- global: a local would be collected and the watcher would stop firing
configWatcher = hs.pathwatcher.new(hs.fs.pathToAbsolute(hs.configdir), reloadOnLuaChange):start()

require("rcmd").start()
require("raycast").start()
require("selection_ocr").start()
require("homerow").start()
require("input_source").start()
if hs.fs.attributes("/Applications/UURemote.app", "mode") == "directory" then
  require("uuremote_lock").start()
  if package.searchpath("uuremote_monitor", package.path) then
    require("uuremote_monitor").start()
  end
end
