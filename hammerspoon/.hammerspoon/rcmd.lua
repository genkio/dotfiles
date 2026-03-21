local M = {}

local launcherHotkeys = {}
local launcherHotkeysEnabled = false
local rightCommandHeld = false
local launcherTap = nil

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
    uniqueAppend(candidates, directory .. "/rcmd.config.lua")
  end

  return candidates
end

local function notifyConfigProblem(alertMessage, logMessage)
  hs.alert.show(alertMessage)
  print("-- rcmd: " .. logMessage)
end

local function loadConfig()
  for _, path in ipairs(configFileCandidates()) do
    if hs.fs.attributes(path) then
      local ok, config = pcall(dofile, path)

      if not ok then
        return nil, ("failed to load %s: %s"):format(path, config)
      end

      return config
    end
  end

  return nil, "create rcmd.config.lua next to rcmd.lua or in " .. hs.configdir
end

local function normalizeBindings(config)
  if type(config) ~= "table" then
    return nil, "rcmd.config.lua must return a table"
  end

  local appBindings = {}

  for key, target in pairs(config) do
    if type(key) ~= "string" then
      return nil, "rcmd.config.lua keys must be strings"
    end

    local normalizedKey = string.lower(key)

    if #normalizedKey ~= 1 then
      return nil, "rcmd.config.lua keys must be single characters"
    end

    if type(target) ~= "string" or target == "" then
      return nil, "rcmd.config.lua values must be non-empty strings"
    end

    appBindings[normalizedKey] = target
  end

  return appBindings
end

local function hasOnlyCommandModifier(flags)
  return flags.cmd and not flags.alt and not flags.ctrl and not flags.shift and not flags.fn
end

local function setLauncherHotkeysEnabled(enabled)
  if launcherHotkeysEnabled == enabled then
    return
  end

  for _, hotkey in pairs(launcherHotkeys) do
    if enabled then
      hotkey:enable()
    else
      hotkey:disable()
    end
  end

  launcherHotkeysEnabled = enabled
end

local function pickWindow(windows)
  if not windows then
    return nil
  end

  for _, window in ipairs(windows) do
    if window:isStandard() then
      return window
    end
  end

  return windows[1]
end

local function firstWindow(app)
  return app:mainWindow() or pickWindow(app:visibleWindows()) or pickWindow(app:allWindows())
end

local function maximizeWindow(window)
  if window:isMinimized() then
    window:unminimize()
  end

  window:focus()

  if window:isFullScreen() then
    window:setFullScreen(false)
    hs.timer.doAfter(0.4, function()
      if window:id() then
        window:maximize(0)
      end
    end)
    return
  end

  window:maximize(0)
end

local function focusAndMaximize(app, retriesRemaining)
  local window = nil

  app:unhide()
  app:activate(true)
  window = firstWindow(app)

  if window then
    maximizeWindow(window)
    return
  end

  if retriesRemaining <= 0 then
    hs.alert.show(("No window available for %s"):format(app:name() or "app"))
    return
  end

  hs.timer.doAfter(0.2, function()
    focusAndMaximize(app, retriesRemaining - 1)
  end)
end

local function lookupTargetFor(appTarget)
  if appTarget:sub(-4) ~= ".app" then
    return appTarget
  end

  local appInfo = hs.application.infoForBundlePath(appTarget)
  if appInfo and appInfo.CFBundleIdentifier then
    return appInfo.CFBundleIdentifier
  end

  return appTarget
end

local function openBoundApp(appBindings, key)
  local appTarget = appBindings[key]
  local lookupTarget = lookupTargetFor(appTarget)
  local app = hs.application.open(appTarget)

  if app then
    focusAndMaximize(app, 15)
    return
  end

  local deadline = hs.timer.secondsSinceEpoch() + 3
  local poller = nil

  poller = hs.timer.doEvery(0.2, function()
    local runningApp = hs.application.get(lookupTarget)

    if runningApp then
      poller:stop()
      focusAndMaximize(runningApp, 15)
      return
    end

    if hs.timer.secondsSinceEpoch() >= deadline then
      poller:stop()
      hs.alert.show(("Could not open %s"):format(appTarget))
    end
  end)
end

function M.start()
  hs.hotkey.setLogLevel("warning")

  local config, configError = loadConfig()

  if not config then
    notifyConfigProblem("rcmd disabled: create rcmd.config.lua", configError)
    return false
  end

  local appBindings, bindingError = normalizeBindings(config)

  if not appBindings then
    notifyConfigProblem("rcmd disabled: fix rcmd.config.lua", bindingError)
    return false
  end

  for key, _ in pairs(appBindings) do
    launcherHotkeys[key] = hs.hotkey.new({ "cmd" }, key, function()
      openBoundApp(appBindings, key)
    end)
  end

  launcherTap = hs.eventtap.new({ hs.eventtap.event.types.flagsChanged }, function(event)
    if event:getKeyCode() == hs.keycodes.map.rightcmd then
      rightCommandHeld = not rightCommandHeld
    end

    setLauncherHotkeysEnabled(rightCommandHeld and hasOnlyCommandModifier(event:getFlags()))
    return false
  end)

  launcherTap:start()
  setLauncherHotkeysEnabled(false)
  return true
end

return M
