local M = {}

local BUNDLE_ID = "com.apple.ScreenContinuity"
-- Window chrome around the mirrored screen, in points.
local INSET = { top = 38, side = 8, bottom = 8 }
-- Marks the events this module posts so its own mouse tap lets them through.
local TAG = 0x44325246
local PROFILE_SETTING = "iphone_mirroring.profile"
local DIRECTIONS = { left = { -1, 0 }, right = { 1, 0 }, up = { 0, -1 }, down = { 0, 1 } }

local types = hs.eventtap.event.types
local userData = hs.eventtap.event.properties.eventSourceUserData

local config = nil
local profileIndex = 1
local profile = nil
local frontmost = false
local enabled = true

-- iPhone Mirroring has a single pointer, owned by the stick, a button or a real click.
local held = {}
local stick = nil
local press = nil
local clicking = false
local cursor = nil

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

local function configFileCandidates()
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

  local candidates = {}
  for _, directory in ipairs(directories) do
    uniqueAppend(candidates, directory .. "/iphone_mirroring.config.lua")
  end
  return candidates
end

local function notifyConfigProblem(message)
  hs.alert.show("iPhone Mirroring config problem")
  print("-- iphone-mirroring: " .. message)
end

local function loadConfig()
  for _, path in ipairs(configFileCandidates()) do
    if hs.fs.attributes(path) then
      local ok, loaded = pcall(dofile, path)

      if not ok then
        return nil, ("failed to load %s: %s"):format(path, loaded)
      end
      if type(loaded) ~= "table" or type(loaded.profiles) ~= "table" or #loaded.profiles == 0 then
        return nil, ("%s must return a table with a non-empty profiles list"):format(path)
      end
      return loaded
    end
  end

  return nil, "create iphone_mirroring.config.lua next to iphone_mirroring.lua"
end

local function keyCodeFor(name, profileName)
  local keyCode = hs.keycodes.map[name]
  if not keyCode then
    notifyConfigProblem(("unknown key %s in profile %s"):format(tostring(name), profileName))
  end
  return keyCode
end

local function compileProfile(spec)
  local name = spec.name or "unnamed"
  local compiled = { name = name, stick = spec.stick, arrows = {}, buttons = {} }

  if spec.stick then
    local keys = spec.stick.keys or {}
    for direction, vector in pairs(DIRECTIONS) do
      local keyCode = keyCodeFor(keys[direction] or direction, name)
      if keyCode then
        compiled.arrows[keyCode] = vector
      end
    end
  end

  for keyName, point in pairs(spec.buttons or {}) do
    local keyCode = keyCodeFor(keyName, name)
    if keyCode then
      compiled.buttons[keyCode] = point
    end
  end

  return compiled
end

local function restoreCursor()
  hs.mouse.absolutePosition(cursor)
  cursor = nil
end

local function post(eventType, point)
  cursor = cursor or hs.mouse.absolutePosition()
  local event = hs.eventtap.event.newMouseEvent(eventType, point)
  event:setProperty(userData, TAG)
  event:post()

  -- Posting moves the cursor once the window server handles the event, so an immediate warp
  -- back can lose. Restore a moment later; the phone follows event locations, not the cursor.
  if M.restoreTimer then
    M.restoreTimer:stop()
  end
  M.restoreTimer = hs.timer.doAfter(0.03, restoreCursor)
end

local function mirroredScreen()
  local app = hs.application.get(BUNDLE_ID)
  local win = app and app:mainWindow()
  if not win then
    return nil
  end

  local frame = win:frame()
  return {
    x = frame.x + INSET.side,
    y = frame.y + INSET.top,
    w = frame.w - 2 * INSET.side,
    h = frame.h - INSET.top - INSET.bottom,
  }
end

local function resolve(point, screen)
  local fraction = type(point) == "function" and point(screen) or point
  return { x = screen.x + screen.w * fraction.x, y = screen.y + screen.h * fraction.y }
end

local function direction()
  local dx, dy = 0, 0
  for keyCode in pairs(held) do
    local vector = profile.arrows[keyCode]
    if vector then
      dx = dx + vector[1]
      dy = dy + vector[2]
    end
  end

  local length = math.sqrt(dx * dx + dy * dy)
  if length == 0 then
    return nil
  end
  return dx / length, dy / length
end

local function liftStick()
  if stick then
    post(types.leftMouseUp, stick.point)
    stick = nil
  end
end

local function liftButton()
  if press then
    post(types.leftMouseUp, press.point)
    press = nil
  end
end

local function updateStick()
  local dx, dy = direction()
  if not dx then
    return liftStick()
  end
  if clicking or press then
    return
  end

  if not stick then
    local screen = mirroredScreen()
    if not screen then
      return
    end

    stick = { origin = resolve(profile.stick, screen), reach = screen.w * profile.stick.reach }
    post(types.leftMouseDown, stick.origin)
  end

  stick.point = { x = stick.origin.x + dx * stick.reach, y = stick.origin.y + dy * stick.reach }
  post(types.leftMouseDragged, stick.point)
end

local function pressButton(keyCode)
  local screen = mirroredScreen()
  if clicking or not screen then
    return
  end

  liftStick()
  liftButton()
  press = { keyCode = keyCode, point = resolve(profile.buttons[keyCode], screen) }
  post(types.leftMouseDown, press.point)
end

local function handleKey(event)
  local keyCode = event:getKeyCode()
  local isButton = profile.buttons[keyCode] ~= nil
  if not profile.arrows[keyCode] and not isButton then
    return false
  end

  local down = event:getType() == types.keyDown
  if down then
    local flags = event:getFlags()
    if flags.cmd or flags.alt or flags.ctrl then
      return false
    end
    if held[keyCode] then
      return true
    end
    held[keyCode] = true
  else
    if not held[keyCode] then
      return false
    end
    held[keyCode] = nil
  end

  if isButton then
    if down then
      pressButton(keyCode)
    elseif press and press.keyCode == keyCode then
      liftButton()
    end
  end

  updateStick()
  return true
end

local function handleMouse(event)
  if event:getProperty(userData) == TAG then
    return false
  end

  local eventType = event:getType()
  if eventType == types.leftMouseDown then
    clicking = true
    if not stick and not press then
      return false
    end

    -- Lift the finger this module holds, then replay the click.
    liftStick()
    liftButton()
    local click = event:copy()
    click:setProperty(userData, TAG)
    click:post()
    return true
  end

  if eventType == types.leftMouseUp then
    clicking = false
    if next(held) then
      M.resumeTimer = hs.timer.doAfter(0.05, updateStick)
    end
    return false
  end

  -- Real mouse movement would drag the held finger.
  return stick ~= nil or press ~= nil
end

local function refresh()
  if frontmost and enabled then
    M.keyTap:start()
    M.mouseTap:start()
  else
    M.keyTap:stop()
    M.mouseTap:stop()
    held = {}
    clicking = false
    liftStick()
    liftButton()
  end

  for _, hotkey in ipairs(M.hotkeys) do
    if frontmost then
      hotkey:enable()
    else
      hotkey:disable()
    end
  end
end

local function selectProfile(index)
  held = {}
  liftStick()
  liftButton()
  profileIndex = index
  profile = compileProfile(config.profiles[index])
  hs.settings.set(PROFILE_SETTING, profile.name)
end

local function savedProfileIndex()
  local saved = hs.settings.get(PROFILE_SETTING)
  for index, spec in ipairs(config.profiles) do
    if spec.name == saved then
      return index
    end
  end
  return 1
end

local function bindHotkey(binding, action)
  if binding then
    table.insert(M.hotkeys, hs.hotkey.new(binding[1], binding[2], action))
  end
end

function M.start()
  local configError
  config, configError = loadConfig()
  if not config then
    notifyConfigProblem(configError)
    return
  end

  selectProfile(savedProfileIndex())

  M.keyTap = hs.eventtap.new({ types.keyDown, types.keyUp }, handleKey)
  M.mouseTap = hs.eventtap.new({
    types.leftMouseDown,
    types.leftMouseUp,
    types.leftMouseDragged,
    types.mouseMoved,
  }, handleMouse)

  M.hotkeys = {}
  bindHotkey(config.toggle, function()
    enabled = not enabled
    refresh()
    hs.alert.show(enabled and ("iPhone keys: " .. profile.name) or "iPhone keys off")
  end)
  bindHotkey(config.nextProfile, function()
    selectProfile(profileIndex % #config.profiles + 1)
    enabled = true
    refresh()
    hs.alert.show("iPhone keys: " .. profile.name)
  end)

  M.appWatcher = hs.application.watcher.new(function(_, event, app)
    if not app or app:bundleID() ~= BUNDLE_ID then
      return
    end

    local w = hs.application.watcher
    if event == w.activated then
      frontmost = true
      refresh()
    elseif event == w.deactivated or event == w.terminated then
      frontmost = false
      refresh()
    end
  end)
  M.appWatcher:start()

  local front = hs.application.frontmostApplication()
  frontmost = front ~= nil and front:bundleID() == BUNDLE_ID
  refresh()
end

return M
