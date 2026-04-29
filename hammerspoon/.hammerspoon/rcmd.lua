-- Rcmd: right-Command app launcher, inspired by rcmd.app
--
-- Hold right-Command and press a letter key to launch or focus an app.
-- Bindings are defined in rcmd.config.lua as single-character keys mapped
-- to app definitions, multi-app pickers, or system actions.
--
-- Features:
--   - Single app bindings: RCmd+B → "Brave Browser" / { app = "Brave Browser", fullscreen = true }
--   - Multi-app picker: RCmd+M → choose between "Mail" / "Messages"
--   - System actions: window tiling, notification center, control center
--   - Config overlay: hold right-Command for 0.5s to see all bindings
--
-- How it works:
--   1. An event tap detects right-Command via raw modifier flag masks
--   2. While held, single-character hotkeys are enabled
--   3. Releasing right-Command disables the hotkeys
--   4. Apps are launched/focused and only sent to macOS fullscreen when configured

local M = {}

local launcherHotkeys = {}
local launcherHotkeysEnabled = false
local rightCommandHeld = false
local launcherTap = nil
local launcherKeyTap = nil
local activeAppPicker = nil
local appPickerDrawings = {}
local appPickerTap = nil
local appPickerTimeout = nil
local configOverlayDrawings = {}
local configOverlayVisible = false
local rightCommandHoldTimer = nil
local currentBindings = {}
local rawFlagMasks = hs.eventtap.event.rawFlagMasks or {}
local leftCommandMask = rawFlagMasks.deviceLeftCommand or 0
local rightCommandMask = rawFlagMasks.deviceRightCommand or 0
local pickerSelectionKeys = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" }
local rightCommandHoldDelay = 0.5
local openBoundApp
local appPickerScreenFrame
local setPickerDrawingStyle

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

local function parseAppTarget(value)
  if type(value) == "string" and value ~= "" then
    return value
  end

  if type(value) == "table" and type(value.app) == "string" and value.app ~= "" then
    return value.app
  end

  return nil
end

local function normalizeAppDefinition(value)
  local appTarget = parseAppTarget(value)

  if not appTarget then
    return nil
  end

  return {
    target = appTarget,
    fullscreen = type(value) == "table" and value.fullscreen == true or false,
  }
end

local function appTargetValue(appTarget)
  if type(appTarget) == "table" then
    return appTarget.target
  end

  return appTarget
end

local function normalizeAppTargets(targets)
  if type(targets) ~= "table" then
    return nil, "rcmd.config.lua multi-app values must be arrays of app names or app tables"
  end

  local appTargets = {}

  for _, value in ipairs(targets) do
    local appDefinition = normalizeAppDefinition(value)

    if not appDefinition then
      return nil, "rcmd.config.lua multi-app values must contain non-empty app names"
    end

    table.insert(appTargets, appDefinition)
  end

  if #appTargets == 0 then
    return nil, "rcmd.config.lua multi-app values must contain at least one app"
  end

  if #appTargets > #pickerSelectionKeys then
    return nil, ("rcmd.config.lua multi-app values support at most %d apps"):format(#pickerSelectionKeys)
  end

  return appTargets
end

local function normalizeBindings(config)
  if type(config) ~= "table" then
    return nil, "rcmd.config.lua must return a table"
  end

  local bindings = {}

  for key, target in pairs(config) do
    if type(key) ~= "string" then
      return nil, "rcmd.config.lua keys must be strings"
    end

    local normalizedKey = string.lower(key)

    if #normalizedKey ~= 1 then
      return nil, "rcmd.config.lua keys must be single characters"
    end

    if type(target) == "string" then
      if target == "" then
        return nil, "rcmd.config.lua string values must be non-empty"
      end

      bindings[normalizedKey] = {
        kind = "app",
        target = normalizeAppDefinition(target),
      }
    elseif type(target) == "table" then
      local appDefinition = normalizeAppDefinition(target)

      if appDefinition then
        bindings[normalizedKey] = {
          kind = "app",
          target = appDefinition,
        }
      elseif type(target.action) == "string" and target.action ~= "" then
        bindings[normalizedKey] = {
          kind = "action",
          target = target.action,
        }
      else
        local appTargets, appTargetError = normalizeAppTargets(target.apps or target)

        if not appTargets then
          return nil, appTargetError
        end

        if #appTargets == 1 then
          bindings[normalizedKey] = {
            kind = "app",
            target = appTargets[1],
          }
        else
          bindings[normalizedKey] = {
            kind = "app_picker",
            targets = appTargets,
          }
        end
      end
    else
      return nil, "rcmd.config.lua values must be strings or tables"
    end
  end

  return bindings
end

local function hasOnlyCommandModifier(flags)
  return flags.cmd and not flags.alt and not flags.ctrl and not flags.shift and not flags.fn
end

local function hasRawFlag(rawFlags, mask)
  return mask ~= 0 and (rawFlags & mask) ~= 0
end

local function hasOnlyRightCommandModifier(event)
  local flags = event:getFlags()

  if not hasOnlyCommandModifier(flags) then
    return false
  end

  local rawFlags = event:rawFlags()

  if rightCommandMask == 0 then
    return event:getKeyCode() == hs.keycodes.map.rightcmd
  end

  -- Raw flags distinguish left/right command keys; generic flags do not.
  return hasRawFlag(rawFlags, rightCommandMask) and not hasRawFlag(rawFlags, leftCommandMask)
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

local function clearConfigOverlayDrawings()
  for _, drawing in ipairs(configOverlayDrawings) do
    drawing:delete()
  end

  configOverlayDrawings = {}
end

local function dismissConfigOverlay()
  clearConfigOverlayDrawings()
  configOverlayVisible = false
end

local function cancelRightCommandHoldTimer()
  if rightCommandHoldTimer then
    rightCommandHoldTimer:stop()
    rightCommandHoldTimer = nil
  end
end

local function appTargetLabel(appTarget)
  appTarget = appTargetValue(appTarget)

  if type(appTarget) ~= "string" or appTarget == "" then
    return "Unknown app"
  end

  local runningApp = hs.application.get(appTarget)

  if runningApp and type(runningApp.name) == "function" then
    local ok, appName = pcall(runningApp.name, runningApp)

    if ok and appName and appName ~= "" then
      return appName
    end
  end

  local bundleName = hs.application.nameForBundleID(appTarget)

  if bundleName then
    return bundleName
  end

  if appTarget:sub(-4) == ".app" then
    local bundlePath = hs.fs.pathToAbsolute(appTarget) or appTarget
    local appInfo = hs.application.infoForBundlePath(bundlePath)

    if appInfo and appInfo.CFBundleName then
      return appInfo.CFBundleName
    end

    return bundlePath:match("([^/]+)%.app$") or appTarget
  end

  return appTarget
end

local function actionTargetLabel(actionTarget)
  local labels = {
    notification_center = "Action: Notification Center",
    notifications = "Action: Notification Center",
    control_center = "Action: Control Center",
    window_left = "Action: Move Window Left",
    window_right = "Action: Move Window Right",
    window_maximize = "Action: Enter Full Screen",
    window_next_screen = "Action: Move Window to Next Screen",
    finder_in_ghostty = "Action: Open Finder Path in Ghostty",
  }

  return labels[actionTarget] or ("Action: %s"):format(actionTarget)
end

local function bindingDisplayLabel(binding)
  if binding.kind == "app" then
    return appTargetLabel(binding.target)
  end

  if binding.kind == "app_picker" then
    local labels = {}

    for _, appTarget in ipairs(binding.targets) do
      labels[#labels + 1] = appTargetLabel(appTarget)
    end

    return table.concat(labels, " / ")
  end

  if binding.kind == "action" then
    return actionTargetLabel(binding.target)
  end

  return "Unknown binding"
end

local function sortedBindingKeys(bindings)
  local keys = {}

  for key in pairs(bindings) do
    keys[#keys + 1] = key
  end

  table.sort(keys)
  return keys
end

local function configOverlayBodyText(bindings)
  local lines = {}

  for _, key in ipairs(sortedBindingKeys(bindings)) do
    lines[#lines + 1] = ("%s  %s"):format(string.upper(key), bindingDisplayLabel(bindings[key]))
  end

  if #lines == 0 then
    lines[1] = "No bindings configured"
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "Release RightCmd to dismiss"
  return table.concat(lines, "\n")
end

local function showConfigOverlay()
  dismissConfigOverlay()

  local frame = appPickerScreenFrame()
  local bodyText = configOverlayBodyText(currentBindings)
  local lineCount = select(2, bodyText:gsub("\n", "\n")) + 1
  local width = 560
  local height = math.min(frame.h - 80, 92 + (lineCount * 24))
  local x = frame.x + math.floor((frame.w - width) / 2)
  local y = frame.y + math.floor((frame.h - height) / 2)
  local title = setPickerDrawingStyle(hs.drawing.text(hs.geometry.rect(x + 20, y + 18, width - 40, 26), "rcmd"))
  local body = setPickerDrawingStyle(hs.drawing.text(hs.geometry.rect(x + 20, y + 52, width - 40, height - 68), bodyText))
  local background = setPickerDrawingStyle(hs.drawing.rectangle(hs.geometry.rect(x, y, width, height)))

  background:setRoundedRectRadii(16, 16)
  background:setFill(true)
  background:setFillColor({ white = 0.08, alpha = 0.97 })
  background:setStroke(true)
  background:setStrokeWidth(2)
  background:setStrokeColor({ white = 1, alpha = 0.12 })

  title:setTextSize(22)
  title:setTextColor({ white = 1, alpha = 1 })

  body:setTextFont("Menlo")
  body:setTextSize(15)
  body:setTextColor({ white = 1, alpha = 0.92 })

  configOverlayDrawings = { background, title, body }
  configOverlayVisible = true

  for _, drawing in ipairs(configOverlayDrawings) do
    drawing:show()
  end
end

local function startRightCommandHoldTimer()
  cancelRightCommandHoldTimer()

  rightCommandHoldTimer = hs.timer.doAfter(rightCommandHoldDelay, function()
    rightCommandHoldTimer = nil

    if rightCommandHeld and not activeAppPicker then
      showConfigOverlay()
    end
  end)
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

local function focusWindow(window)
  if window:isMinimized() then
    window:unminimize()
  end

  window:focus()
end

local function frameWithinTolerance(frame, expectedFrame, tolerance)
  return math.abs(frame.x - expectedFrame.x) <= tolerance
    and math.abs(frame.y - expectedFrame.y) <= tolerance
    and math.abs(frame.w - expectedFrame.w) <= tolerance
    and math.abs(frame.h - expectedFrame.h) <= tolerance
end

local function absoluteFrameForUnit(screenFrame, unitRect)
  return hs.geometry.rect(
    screenFrame.x + (screenFrame.w * unitRect.x),
    screenFrame.y + (screenFrame.h * unitRect.y),
    screenFrame.w * unitRect.w,
    screenFrame.h * unitRect.h
  )
end

local function windowMatchesUnitRect(window, unitRect)
  local screen = window:screen()

  if not screen then
    return false
  end

  return frameWithinTolerance(window:frame(), absoluteFrameForUnit(screen:frame(), unitRect), 12)
end

local function windowIsHalfScreen(window)
  return windowMatchesUnitRect(window, hs.layout.left50) or windowMatchesUnitRect(window, hs.layout.right50)
end

local function fullscreenWindow(window)
  focusWindow(window)

  if window:isFullScreen() then
    return
  end

  window:setFullScreen(true)
end

local function focusApp(app, shouldFullscreen, retriesRemaining)
  local window = nil

  app:unhide()
  app:activate(true)
  window = firstWindow(app)

  if window then
    if shouldFullscreen and not windowIsHalfScreen(window) then
      fullscreenWindow(window)
    else
      focusWindow(window)
    end

    return
  end

  if retriesRemaining <= 0 then
    hs.alert.show(("No window available for %s"):format(app:name() or "app"))
    return
  end

  hs.timer.doAfter(0.2, function()
    focusApp(app, shouldFullscreen, retriesRemaining - 1)
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

local function clearAppPickerDrawings()
  for _, drawing in ipairs(appPickerDrawings) do
    drawing:delete()
  end

  appPickerDrawings = {}
end

local function dismissAppPicker()
  if appPickerTimeout then
    appPickerTimeout:stop()
    appPickerTimeout = nil
  end

  if appPickerTap then
    appPickerTap:stop()
    appPickerTap = nil
  end

  clearAppPickerDrawings()
  activeAppPicker = nil
  setLauncherHotkeysEnabled(rightCommandHeld)
end

appPickerScreenFrame = function()
  local focusedWindow = hs.window.focusedWindow()
  local screen = nil

  if focusedWindow then
    screen = focusedWindow:screen()
  end

  screen = screen or hs.mouse.getCurrentScreen() or hs.screen.mainScreen()
  return screen:frame()
end

local function appPickerBodyText(appTargets)
  local lines = {}

  for index, appTarget in ipairs(appTargets) do
    lines[#lines + 1] = ("%s. %s"):format(pickerSelectionKeys[index], appTargetLabel(appTarget))
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "Esc to cancel"
  return table.concat(lines, "\n")
end

setPickerDrawingStyle = function(drawing)
  drawing:setBehaviorByLabels({ "canJoinAllSpaces" })
  drawing:setLevel("overlay")
  return drawing
end

local function showAppPicker(triggerKey, appTargets)
  dismissAppPicker()

  local frame = appPickerScreenFrame()
  local width = 420
  local height = 108 + (#appTargets * 28)
  local x = frame.x + math.floor((frame.w - width) / 2)
  local y = frame.y + math.floor((frame.h - height) / 2)
  local titleText = ("Select app for %s"):format(string.upper(triggerKey))
  local bodyText = appPickerBodyText(appTargets)
  local background = setPickerDrawingStyle(hs.drawing.rectangle(hs.geometry.rect(x, y, width, height)))
  local title = setPickerDrawingStyle(hs.drawing.text(hs.geometry.rect(x + 20, y + 18, width - 40, 26), titleText))
  local body = setPickerDrawingStyle(hs.drawing.text(hs.geometry.rect(x + 20, y + 50, width - 40, height - 64), bodyText))

  background:setRoundedRectRadii(16, 16)
  background:setFill(true)
  background:setFillColor({ white = 0.1, alpha = 0.96 })
  background:setStroke(true)
  background:setStrokeWidth(2)
  background:setStrokeColor({ white = 1, alpha = 0.12 })

  title:setTextSize(20)
  title:setTextColor({ white = 1, alpha = 1 })

  body:setTextFont("Menlo")
  body:setTextSize(16)
  body:setTextColor({ white = 1, alpha = 0.9 })

  appPickerDrawings = { background, title, body }
  activeAppPicker = {
    targets = appTargets,
  }

  for _, drawing in ipairs(appPickerDrawings) do
    drawing:show()
  end

  setLauncherHotkeysEnabled(false)

  appPickerTap = hs.eventtap.new({
    hs.eventtap.event.types.keyDown,
    hs.eventtap.event.types.leftMouseDown,
    hs.eventtap.event.types.rightMouseDown,
  }, function(event)
    if not activeAppPicker then
      return false
    end

    local eventType = event:getType()

    if eventType == hs.eventtap.event.types.leftMouseDown or eventType == hs.eventtap.event.types.rightMouseDown then
      dismissAppPicker()
      return false
    end

    local keyCode = event:getKeyCode()

    if keyCode == hs.keycodes.map.escape then
      dismissAppPicker()
      return true
    end

    for index, selectionKey in ipairs(pickerSelectionKeys) do
      if keyCode == hs.keycodes.map[selectionKey] then
        local appTarget = activeAppPicker.targets[index]

        if appTarget then
          dismissAppPicker()
          openBoundApp(appTarget)
        end

        return true
      end
    end

    dismissAppPicker()
    return false
  end)

  appPickerTap:start()
  appPickerTimeout = hs.timer.doAfter(5, dismissAppPicker)
end

local function activateAppPickerTarget(index)
  if not activeAppPicker then
    return false
  end

  local appTarget = activeAppPicker.targets[index]

  if not appTarget then
    dismissAppPicker()
    return false
  end

  dismissAppPicker()
  openBoundApp(appTarget)
  return true
end

openBoundApp = function(appBinding)
  local appTarget = appTargetValue(appBinding)
  local shouldFullscreen = type(appBinding) == "table" and appBinding.fullscreen == true
  local lookupTarget = lookupTargetFor(appTarget)
  local app = hs.application.open(appTarget)

  if app then
    focusApp(app, shouldFullscreen, 15)
    return
  end

  local deadline = hs.timer.secondsSinceEpoch() + 3
  local poller = nil

  poller = hs.timer.doEvery(0.2, function()
    local runningApp = hs.application.get(lookupTarget)

    if runningApp then
      poller:stop()
      focusApp(runningApp, shouldFullscreen, 15)
      return
    end

    if hs.timer.secondsSinceEpoch() >= deadline then
      poller:stop()
      hs.alert.show(("Could not open %s"):format(appTarget))
    end
  end)
end

local function moveFocusedWindow(unitRect, missingWindowMessage)
  local window = hs.window.focusedWindow()

  if not window then
    hs.alert.show(missingWindowMessage)
    return
  end

  if window:isFullScreen() then
    window:setFullScreen(false)
    hs.timer.doAfter(0.4, function()
      if window:id() then
        window:moveToUnit(unitRect, 0)
        window:focus()
      end
    end)
    return
  end

  window:moveToUnit(unitRect, 0)
  window:focus()
end

local function fullscreenFocusedWindow(missingWindowMessage)
  local window = hs.window.focusedWindow()

  if not window then
    hs.alert.show(missingWindowMessage)
    return
  end

  fullscreenWindow(window)
end

local function moveFocusedWindowToNextScreen(missingWindowMessage)
  local window = hs.window.focusedWindow()

  if not window then
    hs.alert.show(missingWindowMessage)
    return
  end

  local screens = hs.screen.allScreens()

  if #screens <= 1 then
    return
  end

  local currentScreen = window:screen()
  local currentIndex = nil

  for index, screen in ipairs(screens) do
    if currentScreen and screen:id() == currentScreen:id() then
      currentIndex = index
      break
    end
  end

  if not currentIndex then
    return
  end

  local nextScreen = screens[(currentIndex % #screens) + 1]

  if window:isFullScreen() then
    window:setFullScreen(false)
    hs.timer.doAfter(0.4, function()
      if window:id() then
        window:moveToScreen(nextScreen, false, true)
        window:focus()
      end
    end)
    return
  end

  window:moveToScreen(nextScreen, false, true)
  window:focus()
end

local function openFinderPathInGhostty()
  local frontmostApp = hs.application.frontmostApplication()

  if not frontmostApp or frontmostApp:bundleID() ~= "com.apple.finder" then
    hs.alert.show("Finder is not focused")
    return
  end

  local script = [[
tell application "Finder"
  if not (exists Finder window 1) then
    return {false, "No Finder window is open"}
  end if

  try
    set finderPath to POSIX path of (target of front Finder window as alias)
  on error errMsg
    return {false, errMsg}
  end try
end tell

tell application "Ghostty"
  activate
  set cfg to new surface configuration
  set initial working directory of cfg to finderPath
  new window with configuration cfg
end tell

return {true, finderPath}
]]

  local ok, result, rawOutput = hs.osascript.applescript(script)

  if not ok then
    hs.alert.show("Could not open Finder path in Ghostty")
    print("-- rcmd: failed to open Finder path in Ghostty: " .. tostring(rawOutput or result))
    return
  end

  if type(result) == "table" and result[1] == false then
    hs.alert.show(result[2] or "Could not read Finder path")
  end
end

local function runAction(actionTarget)
  local actionHandlers = {
    notification_center = function()
      hs.eventtap.keyStroke({ "fn" }, "n")
    end,
    notifications = function()
      hs.eventtap.keyStroke({ "fn" }, "n")
    end,
    control_center = function()
      hs.eventtap.keyStroke({ "fn" }, "c")
    end,
    window_left = function()
      moveFocusedWindow(hs.layout.left50, "No focused window to move left")
    end,
    window_right = function()
      moveFocusedWindow(hs.layout.right50, "No focused window to move right")
    end,
    window_maximize = function()
      fullscreenFocusedWindow("No focused window to enter full screen")
    end,
    window_next_screen = function()
      moveFocusedWindowToNextScreen("No focused window to move")
    end,
    finder_in_ghostty = openFinderPathInGhostty,
  }

  local handler = actionHandlers[actionTarget]

  if not handler then
    hs.alert.show(("Unknown rcmd action: %s"):format(actionTarget))
    return
  end

  handler()
end

local function triggerBinding(triggerKey, binding)
  cancelRightCommandHoldTimer()
  dismissConfigOverlay()

  if binding.kind == "app" then
    openBoundApp(binding.target)
    return
  end

  if binding.kind == "app_picker" then
    showAppPicker(triggerKey, binding.targets)
    return
  end

  if binding.kind == "action" then
    runAction(binding.target)
  end
end

function M.start()
  hs.hotkey.setLogLevel("warning")

  local config, configError = loadConfig()

  if not config then
    notifyConfigProblem("rcmd disabled: create rcmd.config.lua", configError)
    return false
  end

  local bindings, bindingError = normalizeBindings(config)

  if not bindings then
    notifyConfigProblem("rcmd disabled: fix rcmd.config.lua", bindingError)
    return false
  end

  for key, binding in pairs(bindings) do
    launcherHotkeys[key] = hs.hotkey.new({ "cmd" }, key, function()
      triggerBinding(key, binding)
    end)
  end

  currentBindings = bindings

  launcherTap = hs.eventtap.new({ hs.eventtap.event.types.flagsChanged }, function(event)
    local wasRightCommandHeld = rightCommandHeld
    rightCommandHeld = hasOnlyRightCommandModifier(event)

    if activeAppPicker and wasRightCommandHeld and not rightCommandHeld then
      activateAppPickerTarget(1)
      return false
    end

    if rightCommandHeld and not wasRightCommandHeld then
      startRightCommandHoldTimer()
    elseif not rightCommandHeld then
      cancelRightCommandHoldTimer()
      dismissConfigOverlay()
    end

    if not activeAppPicker then
      setLauncherHotkeysEnabled(rightCommandHeld)
    end

    return false
  end)

  launcherKeyTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function()
    if not rightCommandHeld or activeAppPicker then
      return false
    end

    cancelRightCommandHoldTimer()
    dismissConfigOverlay()
    return false
  end)

  launcherTap:start()
  launcherKeyTap:start()
  setLauncherHotkeysEnabled(false)
  return true
end

return M
