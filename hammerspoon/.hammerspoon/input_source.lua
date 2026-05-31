-- App-specific input source defaults.
--
-- Configure app -> input source mappings in input_source.config.lua. Each time
-- macOS activates an app, this module switches to that app's configured input
-- source when one is defined.

local M = {}

local currentConfig = nil

local function parentDirectory(path)
  return path:match("^(.*)/[^/]+$")
end

local function uniqueAppend(list, value)
  if not value then
    return
  end

  for _, existingValue in ipairs(list) do
    if existingValue == value then
      return
    end
  end

  table.insert(list, value)
end

local function sourceDirectories()
  local directories = {}
  local source = debug.getinfo(1, "S").source

  if type(source) == "string" and source:sub(1, 1) == "@" then
    local modulePath = source:sub(2)
    local resolvedPath = hs.fs.pathToAbsolute(modulePath)

    uniqueAppend(directories, parentDirectory(modulePath))

    if resolvedPath and resolvedPath ~= modulePath then
      uniqueAppend(directories, parentDirectory(resolvedPath))
    end
  end

  uniqueAppend(directories, hs.configdir)
  return directories
end

local function configFileCandidates()
  local candidates = {}

  for _, directory in ipairs(sourceDirectories()) do
    uniqueAppend(candidates, directory .. "/input_source.config.lua")
  end

  return candidates
end

local function notifyConfigProblem(message)
  hs.alert.show("Input source config problem")
  print("-- input-source: " .. message)
end

local function loadConfig()
  for _, path in ipairs(configFileCandidates()) do
    if hs.fs.attributes(path) then
      local ok, config = pcall(dofile, path)

      if not ok then
        notifyConfigProblem(("failed to load %s: %s"):format(path, config))
        return { sources = {}, apps = {} }
      end

      if type(config) ~= "table" then
        notifyConfigProblem(("config must return a table: %s"):format(path))
        return { sources = {}, apps = {} }
      end

      return config
    end
  end

  notifyConfigProblem("create input_source.config.lua next to input_source.lua")
  return { sources = {}, apps = {} }
end

local function resolveSourceID(value)
  if type(value) == "table" then
    value = value.source or value.input or value.id
  end

  if type(value) ~= "string" or value == "" then
    return nil
  end

  local sources = currentConfig.sources or {}
  return sources[value] or value
end

local function configuredSourceForApp(app)
  if not app then
    return nil
  end

  local apps = currentConfig.apps or {}
  return resolveSourceID(apps[app:bundleID()] or apps[app:name()])
end

local function applyForApp(app)
  local sourceID = configuredSourceForApp(app)
  if not sourceID then
    return
  end

  if hs.keycodes.currentSourceID() ~= sourceID then
    hs.keycodes.currentSourceID(sourceID)
  end
end

function M.start()
  currentConfig = loadConfig()

  M.appWatcher = hs.application.watcher.new(function(_, event, app)
    if event == hs.application.watcher.activated then
      applyForApp(app)
    end
  end)
  M.appWatcher:start()

  applyForApp(hs.application.frontmostApplication())
end

return M
