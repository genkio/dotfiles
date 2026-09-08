-- Start the screen saver when a UURemote session ends.
--
-- UURemote's own "lock on disconnect" gives a bare lock screen, and macOS
-- won't let anything (ScreenSaverEngine included) draw over it afterwards.
-- Starting the saver first gets Fliqlo and, with askForPasswordDelay=0, locks
-- just the same. UURemote has no hook for this, so we poll UURemoteServer's
-- peer connections and fire on the connected -> disconnected edge. Requires
-- UURemote's lock-on-disconnect to be OFF, otherwise its lock wins the race.

local M = {}

local probe = require("uuremote_probe")
local DISCONNECT_POLLS = 2

local connected = false
local zeroPolls = 0
local locked = false
local saverRunning = false

local function log(message)
  print("-- uuremote-lock: " .. message)
end

local function onDisconnected()
  if locked or saverRunning then
    log("disconnected, already locked or saver running")
    return
  end

  log("disconnected, starting screen saver")
  hs.caffeinate.startScreensaver()
end

local function handleCount(count)
  if count == nil then
    zeroPolls = 0
    return
  end
  if count > 0 then
    zeroPolls = 0
    if not connected then
      connected = true
      log(("connected (%d peer connections)"):format(count))
    end
    return
  end

  if not connected then
    return
  end

  zeroPolls = zeroPolls + 1
  if zeroPolls >= DISCONNECT_POLLS then
    connected = false
    zeroPolls = 0
    onDisconnected()
  end
end

function M.start()
  M.watcher = hs.caffeinate.watcher.new(function(event)
    local w = hs.caffeinate.watcher
    if event == w.screensDidLock then
      locked = true
    elseif event == w.screensDidUnlock then
      locked = false
    elseif event == w.screensaverDidStart then
      saverRunning = true
    elseif event == w.screensaverDidStop then
      saverRunning = false
    end
  end)
  M.watcher:start()

  probe.subscribe(function(sample)
    handleCount(sample and sample.peerCount or nil)
  end)
  probe.start()
end

return M
