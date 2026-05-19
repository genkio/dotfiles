-- F-key remapping for an Apple Wireless Keyboard with broken Esc and `
-- keys:
--   F1 -> Escape
--   F2 -> grave (`)
--
-- Requires macOS "Use F1, F2, etc. keys as standard function keys" to be
-- enabled (set globally by scripts/macos-bootstrap.sh via
-- com.apple.keyboard.fnState). With that setting on, F1/F2 alone emit
-- keyboard keycodes that CGEventTap can intercept, and fn+F1/F2 emit
-- the consumer brightness events that macOS routes natively (preserving
-- brightness control with HUD). Without the setting, F1/F2 alone on the
-- Apple Wireless Keyboard bypass CGEventTap entirely (verified
-- diagnostically) and cannot be intercepted from Hammerspoon.

local M = {}

local eventtap = hs.eventtap
local types = hs.eventtap.event.types

local F1_KEYCODE = 122
local F2_KEYCODE = 120

local keyboardTap = eventtap.new({ types.keyDown }, function(e)
  local keyCode = e:getKeyCode()
  if keyCode == F1_KEYCODE then
    eventtap.keyStroke({}, "escape", 0)
    return true
  elseif keyCode == F2_KEYCODE then
    eventtap.keyStroke({}, "`", 0)
    return true
  end
  return false
end)

function M.start()
  keyboardTap:start()
  return M
end

function M.stop()
  keyboardTap:stop()
end

return M
