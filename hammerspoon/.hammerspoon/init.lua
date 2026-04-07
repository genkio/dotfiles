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

require("rcmd").start()
require("selection_ocr").start()
