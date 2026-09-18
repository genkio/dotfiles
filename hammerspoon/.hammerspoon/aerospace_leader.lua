
local M = {}

local MODE = "rcmd"
local BUNDLE_ID = "bobko.aerospace"

local aerospaceBinary = nil
local leaderHeld = false
local flagsTap = nil
local keyTap = nil
local bindings = {}
local refreshTask = nil
local pollTimer = nil
local listeners = {}
local aerospaceRunning = false

local rawFlagMasks = hs.eventtap.event.rawFlagMasks or {}
local leftCommandMask = rawFlagMasks.deviceLeftCommand or 0
local rightCommandMask = rawFlagMasks.deviceRightCommand or 0

local keyNameOverrides = {
  ["return"] = "enter",
  ["escape"] = "esc",
  ["delete"] = "backspace",
  ["forwarddelete"] = "forwardDelete",
  ["pageup"] = "pageUp",
  ["pagedown"] = "pageDown",
  ["/"] = "slash",
  [","] = "comma",
  ["."] = "period",
  ["-"] = "minus",
  ["="] = "equal",
  [";"] = "semicolon",
  ["'"] = "quote",
  ["`"] = "backtick",
  ["\\"] = "backslash",
  ["["] = "leftSquareBracket",
  ["]"] = "rightSquareBracket",
}

local function findAerospace()
  for _, path in ipairs({ "/opt/homebrew/bin/aerospace", "/usr/local/bin/aerospace" }) do
    if hs.fs.attributes(path) then
      return path
    end
  end

  return nil
end

local function isRightCommandOnly(event)
  local flags = event:getFlags()

  if not flags.cmd or flags.alt or flags.ctrl or flags.fn then
    return false
  end

  local rawFlags = event:rawFlags()

  return (rawFlags & rightCommandMask) ~= 0 and (rawFlags & leftCommandMask) == 0
end

local function bindingName(event)
  local keyName = hs.keycodes.map[event:getKeyCode()]

  if type(keyName) ~= "string" then
    return nil
  end

  keyName = keyNameOverrides[keyName] or keyName

  if event:getFlags().shift then
    return "shift-" .. keyName
  end

  return keyName
end

local function refreshBindings()
  if refreshTask and refreshTask:isRunning() then
    return
  end

  refreshTask = hs.task.new(aerospaceBinary, function(exitCode, stdout)
    if exitCode ~= 0 then
      return
    end

    local ok, parsed = pcall(hs.json.decode, stdout)

    if ok and type(parsed) == "table" then
      bindings = parsed
    end
  end, { "config", "--get", "mode." .. MODE .. ".binding", "--json" })

  refreshTask:start()
end

local function isRunning()
  return #hs.application.applicationsForBundleID(BUNDLE_ID) > 0
end

local function setRunning(running)
  if aerospaceRunning == running then
    return
  end

  aerospaceRunning = running
  leaderHeld = false

  if running then
    refreshBindings()
  end

  for _, listener in ipairs(listeners) do
    listener(running)
  end
end

function M.onRunningChanged(listener)
  listeners[#listeners + 1] = listener
  listener(aerospaceRunning)
end

function M.isActive()
  return aerospaceRunning
end

function M.start()
  aerospaceBinary = findAerospace()

  if not aerospaceBinary then
    hs.alert.show("aerospace leader off: aerospace binary not found")
    return false
  end

  if rightCommandMask == 0 then
    hs.alert.show("aerospace leader off: no raw modifier flags")
    return false
  end

  aerospaceRunning = isRunning()
  pollTimer = hs.timer.doEvery(2, function()
    setRunning(isRunning())
  end)

  if aerospaceRunning then
    refreshBindings()
  end

  flagsTap = hs.eventtap.new({ hs.eventtap.event.types.flagsChanged }, function(event)
    if not aerospaceRunning then
      return false
    end

    local held = isRightCommandOnly(event)

    if held and not leaderHeld then
      refreshBindings()
    end

    leaderHeld = held
    return false
  end)

  keyTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(event)
    if not leaderHeld then
      return false
    end

    local binding = bindingName(event)

    if not binding or bindings[binding] == nil then
      return false
    end

    hs.task.new(aerospaceBinary, nil, { "trigger-binding", "--mode", MODE, "--", binding }):start()
    return true
  end)

  flagsTap:start()
  keyTap:start()
  return true
end

return M
