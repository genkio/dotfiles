
local M = {}

local TIMEOUT = 8

local aerospaceBinary = nil
local canvases = {}
local keyTap = nil
local timeoutTimer = nil
local listTask = nil

local function findAerospace()
  for _, path in ipairs({ "/opt/homebrew/bin/aerospace", "/usr/local/bin/aerospace" }) do
    if hs.fs.attributes(path) then
      return path
    end
  end

  return nil
end

local function dismiss()
  if keyTap then
    keyTap:stop()
    keyTap = nil
  end

  if timeoutTimer then
    timeoutTimer:stop()
    timeoutTimer = nil
  end

  for _, canvas in ipairs(canvases) do
    canvas:delete()
  end

  canvases = {}
end

local function showBadge(screen, monitorId, monitorName)
  local frame = screen:frame()
  local size = { w = 360, h = 260 }
  local canvas = hs.canvas.new({
    x = frame.x + (frame.w - size.w) / 2,
    y = frame.y + (frame.h - size.h) / 2,
    w = size.w,
    h = size.h,
  })

  canvas:appendElements({
    type = "rectangle",
    action = "fill",
    roundedRectRadii = { xRadius = 24, yRadius = 24 },
    fillColor = { red = 0.1, green = 0.1, blue = 0.12, alpha = 0.85 },
  }, {
    type = "text",
    text = tostring(monitorId),
    textSize = 140,
    textColor = { white = 1 },
    textAlignment = "center",
    textFont = ".AppleSystemUIFont",
    frame = { x = 0, y = 20, w = size.w, h = 170 },
  }, {
    type = "text",
    text = monitorName,
    textSize = 18,
    textColor = { white = 0.85 },
    textAlignment = "center",
    textFont = ".AppleSystemUIFont",
    frame = { x = 0, y = 200, w = size.w, h = 40 },
  })

  canvas:level(hs.canvas.windowLevels.overlay)
  canvas:show()
  canvases[#canvases + 1] = canvas
end

local function launchOn(monitorId, app)
  hs.task.new(aerospaceBinary, function()
    hs.task.new("/usr/bin/open", nil, { "-a", app }):start()
  end, { "focus-monitor", tostring(monitorId) }):start()
end

local function listen(monitorIds, app)
  keyTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(event)
    local keyName = hs.keycodes.map[event:getKeyCode()]

    if keyName == "escape" then
      dismiss()
      return true
    end

    local flags = event:getFlags()

    if flags.cmd or flags.alt or flags.ctrl or flags.fn then
      return false
    end

    if monitorIds[keyName] then
      dismiss()
      launchOn(monitorIds[keyName], app)
    end

    return true
  end)

  keyTap:start()
  timeoutTimer = hs.timer.doAfter(TIMEOUT, dismiss)
end

local function parseMonitors(stdout)
  local monitors = {}

  for line in stdout:gmatch("[^\n]+") do
    local id, appKitIndex, name = line:match("^(%d+)|(%d+)|(.*)$")

    if id then
      monitors[#monitors + 1] = { id = tonumber(id), appKitIndex = tonumber(appKitIndex), name = name }
    end
  end

  return monitors
end

function M.pick(app)
  aerospaceBinary = aerospaceBinary or findAerospace()

  if not aerospaceBinary then
    hs.task.new("/usr/bin/open", nil, { "-a", app }):start()
    return
  end

  dismiss()

  if listTask and listTask:isRunning() then
    listTask:terminate()
  end

  listTask = hs.task.new(aerospaceBinary, function(exitCode, stdout)
    local monitors = exitCode == 0 and parseMonitors(stdout) or {}
    local screens = hs.screen.allScreens()
    local monitorIds = {}

    for _, monitor in ipairs(monitors) do
      local screen = screens[monitor.appKitIndex]

      if screen and monitor.id < 10 then
        showBadge(screen, monitor.id, monitor.name)
        monitorIds[tostring(monitor.id)] = monitor.id
      end
    end

    if next(monitorIds) == nil then
      hs.task.new("/usr/bin/open", nil, { "-a", app }):start()
      return
    end

    listen(monitorIds, app)
  end, {
    "list-monitors",
    "--format",
    "%{monitor-id}|%{monitor-appkit-nsscreen-screens-id}|%{monitor-name}",
  })

  listTask:start()
end

M.dismiss = dismiss

return M
