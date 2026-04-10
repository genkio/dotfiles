-- Homerow: keyboard-driven navigation for macOS, inspired by homerow.app
--
-- Press Ctrl+. to enter hint mode. Yellow labels appear on all actionable
-- UI elements (buttons, links, text fields, list rows, tabs, etc.) in the
-- focused window. Type the hint characters to activate the target element.
--
-- How it works:
--   1. Walks the Accessibility tree (AXChildren) of the frontmost window
--      using breadth-first search, collecting interactive elements
--   2. Assigns short labels from home-row characters (asdfjklgh)
--   3. Draws labels as an overlay using hs.canvas
--   4. Captures keystrokes via hs.eventtap to match hints
--   5. Activates the matched element with a synthetic mouse click
--
-- Keybindings while in hint mode:
--   [hint chars]  - narrow down / select a target
--   Backspace     - undo last character
--   Escape        - dismiss (or any non-hint key)
--
-- The overlay auto-dismisses after DISMISS_TIMEOUT seconds.

local M = {}

local axuielement = require("hs.axuielement")
local canvas = require("hs.canvas")
local eventtap = require("hs.eventtap")

-- Configuration
local HINT_CHARS = "asdfjklgh"
local TRIGGER_MODS = { "ctrl" }
local TRIGGER_KEY = "."
local DISMISS_TIMEOUT = 10
local MAX_DEPTH = 30
local WALK_DEADLINE_SECS = 1.0

-- Visual style
local BADGE_BG = { red = 0.96, green = 0.76, blue = 0.07, alpha = 0.95 }
local BADGE_BORDER = { red = 0.72, green = 0.56, blue = 0.0, alpha = 0.8 }
local BADGE_TEXT_COLOR = { red = 0.08, green = 0.08, blue = 0.08, alpha = 1 }
local BADGE_FONT_NAME = "Menlo-Bold"
local BADGE_FONT_SIZE = 11
local BADGE_PADDING_X = 4
local BADGE_PADDING_Y = 2
local BADGE_CORNER_RADIUS = 3
local DIM_OVERLAY_COLOR = { white = 0, alpha = 0.12 }
local MATCHED_BG = { red = 0.2, green = 0.8, blue = 0.3, alpha = 0.95 }
local MATCHED_BORDER = { red = 0.1, green = 0.6, blue = 0.2, alpha = 0.8 }
local MATCHED_TEXT_COLOR = { white = 1, alpha = 1 }

-- State
local hintCanvas = nil
local keyTap = nil
local hotkey = nil
local inputBuffer = ""
local activeHints = {}
local isActive = false
local dismissTimer = nil
local screenFrame = nil
local scanCanvas = nil

-- Roles that are inherently interactive
local interactiveRoles = {
  AXButton = true,
  AXLink = true,
  AXTextField = true,
  AXTextArea = true,
  AXCheckBox = true,
  AXRadioButton = true,
  AXPopUpButton = true,
  AXComboBox = true,
  AXMenuButton = true,
  AXMenuItem = true,
  AXSlider = true,
  AXIncrementor = true,
  AXDisclosureTriangle = true,
  AXRow = true,
  AXCell = true,
  AXOutlineRow = true,
  AXTabGroup = true,
  AXToolbar = true,
}

-- Maximum number of hints we can generate (numChars^2 for two-char hints)
local MAX_HINTS = #HINT_CHARS * #HINT_CHARS

-- Generate fixed-length hint labels for a given count
-- Uses single chars when count <= numChars, two chars otherwise
local function generateHints(count)
  local chars = {}
  for c in HINT_CHARS:gmatch(".") do
    table.insert(chars, c)
  end
  local numChars = #chars

  if count <= 0 then return {} end

  if count <= numChars then
    local result = {}
    for i = 1, count do
      result[i] = chars[i]
    end
    return result
  end

  local result = {}
  for i = 1, numChars do
    for j = 1, numChars do
      table.insert(result, chars[i] .. chars[j])
      if #result >= count then return result end
    end
  end

  return result
end

-- Roles that are pure layout containers — never actionable themselves,
-- and calling actionNames() on them wastes time
local skipActionCheckRoles = {
  AXScrollArea = true,
  AXSplitGroup = true,
  AXSplitter = true,
  AXLayoutArea = true,
  AXWindow = true,
  AXApplication = true,
  AXScrollBar = true,
  AXValueIndicator = true,
}

-- Check if an element is actionable and visible within the window frame
local function isActionable(element, windowFrame)
  local role = element:attributeValue("AXRole")
  if not role then return nil end

  local enabled = element:attributeValue("AXEnabled")
  if enabled == false then return nil end

  local pos = element:attributeValue("AXPosition")
  local size = element:attributeValue("AXSize")
  if not pos or not size then return nil end
  if size.w < 5 or size.h < 5 then return nil end

  -- Must be within window bounds
  local cx = pos.x + size.w / 2
  local cy = pos.y + size.h / 2
  if cx < windowFrame.x or cx > windowFrame.x + windowFrame.w
    or cy < windowFrame.y or cy > windowFrame.y + windowFrame.h then
    return nil
  end

  -- Check if interactive by role
  if interactiveRoles[role] then
    return { role = role, position = pos, size = size, center = { x = cx, y = cy } }
  end

  -- Skip action check for known non-interactive containers
  if skipActionCheckRoles[role] then return nil end

  -- For other roles (AXStaticText, AXImage, AXGroup, etc.),
  -- check if element exposes a press or open action
  local actions = element:actionNames()
  if actions then
    for _, action in ipairs(actions) do
      if action == "AXPress" or action == "AXOpen" then
        return { role = role, position = pos, size = size, center = { x = cx, y = cy } }
      end
    end
  end

  return nil
end

-- Check if an element's bounds overlap the visible window area
-- Used to prune entire subtrees that are off-screen
local function isOnScreen(element, windowFrame)
  local ok, pos, size
  ok, pos = pcall(function() return element:attributeValue("AXPosition") end)
  if not ok or not pos then return true end -- assume visible if we can't tell
  ok, size = pcall(function() return element:attributeValue("AXSize") end)
  if not ok or not size then return true end

  -- Element is off-screen if it's entirely outside the window frame
  if pos.x + size.w < windowFrame.x or pos.x > windowFrame.x + windowFrame.w then return false end
  if pos.y + size.h < windowFrame.y or pos.y > windowFrame.y + windowFrame.h then return false end
  return true
end

-- Collect actionable elements using breadth-first search
-- BFS ensures even coverage across all areas of the window (toolbar, sidebar,
-- content) rather than exhausting one deep branch before visiting others
local function collectElements(axWin, winFrame)
  local deadlineNs = hs.timer.absoluteTime() + (WALK_DEADLINE_SECS * 1e9)
  local elements = {}
  local visited = 0

  -- BFS queue entries: { element, depth }
  local queue = { { axWin, 0 } }
  local head = 1

  while head <= #queue do
    if #elements >= MAX_HINTS then break end

    -- Check wall-clock deadline periodically
    visited = visited + 1
    if visited % 40 == 0 then
      if hs.timer.absoluteTime() >= deadlineNs then break end
    end

    local entry = queue[head]
    head = head + 1
    local elem, depth = entry[1], entry[2]

    if depth > MAX_DEPTH then goto continue end

    -- Check if this element is actionable
    if depth > 0 then -- skip root window element
      local ok, info = pcall(isActionable, elem, winFrame)
      if ok and info then
        -- Dedup: skip if this element's center falls inside a larger
        -- already-collected element (parent/child overlap from BFS)
        local dominated = false
        local area = info.size.w * info.size.h
        for _, existing in ipairs(elements) do
          local ea = existing.size.w * existing.size.h
          if area < ea * 0.95
            and info.center.x >= existing.position.x
            and info.center.x <= existing.position.x + existing.size.w
            and info.center.y >= existing.position.y
            and info.center.y <= existing.position.y + existing.size.h then
            dominated = true
            break
          end
        end
        if not dominated then
          info.element = elem
          table.insert(elements, info)
        end
      end
    end

    -- Enqueue children, pruning off-screen subtrees
    local ok, children = pcall(function() return elem:attributeValue("AXChildren") end)
    if ok and children then
      for _, child in ipairs(children) do
        if isOnScreen(child, winFrame) then
          table.insert(queue, { child, depth + 1 })
        end
      end
    end

    ::continue::
  end

  -- Sort top-to-bottom, left-to-right for intuitive hint assignment
  table.sort(elements, function(a, b)
    local rowA = math.floor(a.center.y / 20)
    local rowB = math.floor(b.center.y / 20)
    if rowA ~= rowB then return rowA < rowB end
    return a.center.x < b.center.x
  end)

  return elements
end

-- Build and display the hint overlay canvas
local function showHints(hints, frame)
  if hintCanvas then
    hintCanvas:delete()
    hintCanvas = nil
  end

  hintCanvas = canvas.new(frame)

  -- Dim overlay
  hintCanvas:insertElement({
    type = "rectangle",
    fillColor = DIM_OVERLAY_COLOR,
    strokeColor = { alpha = 0 },
    frame = { x = 0, y = 0, w = frame.w, h = frame.h },
  })

  local charWidth = BADGE_FONT_SIZE * 0.65

  for _, hint in ipairs(hints) do
    local label = hint.label
    local isMatched = #inputBuffer > 0 and label:sub(1, #inputBuffer) == inputBuffer

    local textWidth = #label * charWidth
    local textHeight = BADGE_FONT_SIZE + 2
    local bw = textWidth + BADGE_PADDING_X * 2
    local bh = textHeight + BADGE_PADDING_Y * 2

    -- Position at top-left of element
    local bx = hint.position.x - frame.x
    local by = hint.position.y - frame.y - bh / 2

    -- Clamp to screen bounds
    bx = math.max(0, math.min(bx, frame.w - bw))
    by = math.max(0, math.min(by, frame.h - bh))

    local bgColor = isMatched and MATCHED_BG or BADGE_BG
    local borderColor = isMatched and MATCHED_BORDER or BADGE_BORDER
    local textColor = isMatched and MATCHED_TEXT_COLOR or BADGE_TEXT_COLOR

    -- Badge background
    hintCanvas:insertElement({
      type = "rectangle",
      fillColor = bgColor,
      strokeColor = borderColor,
      strokeWidth = 1,
      roundedRectRadii = { xRadius = BADGE_CORNER_RADIUS, yRadius = BADGE_CORNER_RADIUS },
      frame = { x = bx, y = by, w = bw, h = bh },
    })

    -- Badge text
    hintCanvas:insertElement({
      type = "text",
      text = label:upper(),
      textColor = textColor,
      textFont = BADGE_FONT_NAME,
      textSize = BADGE_FONT_SIZE,
      textAlignment = "center",
      frame = { x = bx, y = by + BADGE_PADDING_Y - 1, w = bw, h = bh - BADGE_PADDING_Y },
    })
  end

  hintCanvas:level("overlay")
  hintCanvas:behavior("canJoinAllSpaces")
  hintCanvas:clickActivating(false)
  hintCanvas:show()
end

-- Redraw overlay showing only hints that match the current input
local function updateHints()
  if not screenFrame then return end

  local matching = {}
  for _, hint in ipairs(activeHints) do
    if hint.label:sub(1, #inputBuffer) == inputBuffer then
      table.insert(matching, hint)
    end
  end

  showHints(matching, screenFrame)
end

-- Perform the action on the selected element
local function activateElement(hint)
  local elem = hint.element
  local role = hint.role or ""

  -- Focus text inputs before clicking to place cursor
  if role == "AXTextField" or role == "AXTextArea" or role == "AXComboBox" then
    pcall(function() elem:setAttributeValue("AXFocused", true) end)
  end

  -- Synthetic click is universally reliable for all on-screen elements.
  -- AXPress looks appealing but silently fails on many controls (terminal
  -- tabs, browser elements, some buttons) — pcall returns true but nothing
  -- happens, with no way to detect the failure.
  eventtap.leftClick(hint.center)
end

-- Show a subtle scan indicator at the top-right corner
local function showScanIndicator(frame)
  if scanCanvas then scanCanvas:delete() end

  local w, h = 16, 16
  local x = frame.x + frame.w - w - 12
  local y = frame.y + 8

  scanCanvas = canvas.new({ x = x, y = y, w = w, h = h })
  scanCanvas:insertElement({
    type = "circle",
    fillColor = BADGE_BG,
    strokeColor = { alpha = 0 },
    center = { x = w / 2, y = h / 2 },
    radius = w / 2 - 1,
  })
  scanCanvas:level("overlay")
  scanCanvas:behavior("canJoinAllSpaces")
  scanCanvas:clickActivating(false)
  scanCanvas:show()
end

local function hideScanIndicator()
  if scanCanvas then
    scanCanvas:delete()
    scanCanvas = nil
  end
end

-- Clean up all state and dismiss the overlay
local function exitHintMode()
  isActive = false
  inputBuffer = ""
  activeHints = {}
  screenFrame = nil

  hideScanIndicator()

  if hintCanvas then
    hintCanvas:delete()
    hintCanvas = nil
  end

  if keyTap then
    keyTap:stop()
    keyTap = nil
  end

  if dismissTimer then
    dismissTimer:stop()
    dismissTimer = nil
  end
end

-- Start the key capture event tap for hint selection
local function startKeyTap()
  keyTap = eventtap.new({ eventtap.event.types.keyDown }, function(event)
    local keyCode = event:getKeyCode()
    local char = event:getCharacters():lower()

    -- Escape: dismiss
    if keyCode == 53 then
      exitHintMode()
      return true
    end

    -- Backspace: remove last character
    if keyCode == 51 then
      if #inputBuffer > 0 then
        inputBuffer = inputBuffer:sub(1, -2)
        updateHints()
      end
      return true
    end

    -- Ignore non-hint characters
    if not HINT_CHARS:find(char, 1, true) then
      exitHintMode()
      return true
    end

    inputBuffer = inputBuffer .. char

    -- Find matching hints
    local matches = {}
    for _, hint in ipairs(activeHints) do
      if hint.label:sub(1, #inputBuffer) == inputBuffer then
        table.insert(matches, hint)
      end
    end

    -- No matches: dismiss
    if #matches == 0 then
      exitHintMode()
      return true
    end

    -- Exact single match: activate
    if #matches == 1 and matches[1].label == inputBuffer then
      local target = matches[1]
      exitHintMode()
      -- Brief delay so the window server fully removes the overlay
      -- before the synthetic click lands on the target app
      hs.timer.doAfter(0.05, function()
        activateElement(target)
      end)
      return true
    end

    -- Multiple partial matches: update display
    updateHints()
    return true
  end)

  keyTap:start()
end

-- Core logic: walk the tree, build hints, show overlay
local function performScan(axWin, winFrame)
  if not isActive then return end

  hideScanIndicator()

  local elements = collectElements(axWin, winFrame)

  if #elements == 0 then
    hs.alert.show("No actionable elements found", 1)
    isActive = false
    return
  end

  local labels = generateHints(#elements)
  activeHints = {}
  for i, elem in ipairs(elements) do
    elem.label = labels[i]
    table.insert(activeHints, elem)
  end

  showHints(activeHints, screenFrame)
  startKeyTap()

  -- Auto-dismiss after timeout
  dismissTimer = hs.timer.doAfter(DISMISS_TIMEOUT, function()
    if isActive then exitHintMode() end
  end)
end

-- Enter hint mode: show indicator, then defer the tree walk so the
-- indicator canvas renders before the synchronous work blocks Lua
local function enterHintMode()
  if isActive then
    exitHintMode()
    return
  end

  local app = hs.application.frontmostApplication()
  if not app then return end

  local win = app:focusedWindow()
  if not win then return end

  local winFrame = win:frame()
  local screen = win:screen() or hs.screen.mainScreen()
  screenFrame = screen:fullFrame()

  local axWin = axuielement.windowElement(win)
  if not axWin then return end

  isActive = true
  inputBuffer = ""

  showScanIndicator(screenFrame)

  -- Defer by one run-loop cycle so the indicator dot actually appears
  hs.timer.doAfter(0.01, function()
    performScan(axWin, winFrame)
  end)
end

function M.start()
  hotkey = hs.hotkey.bind(TRIGGER_MODS, TRIGGER_KEY, enterHintMode)
  return true
end

function M.stop()
  exitHintMode()
  if hotkey then
    hotkey:delete()
    hotkey = nil
  end
end

return M
