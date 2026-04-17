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
local DISMISS_TIMEOUT = 15
local MAX_DEPTH = 30
local WALK_DEADLINE_SECS = 1.5
local SCAN_MENUBAR = true

-- Visual style
local BADGE_BG = { red = 0.96, green = 0.76, blue = 0.07, alpha = 0.95 }
local BADGE_BORDER = { red = 0.72, green = 0.56, blue = 0.0, alpha = 0.8 }
local BADGE_TEXT_COLOR = { red = 0.08, green = 0.08, blue = 0.08, alpha = 1 }
local BADGE_FONT_NAME = "Menlo-Bold"
local BADGE_FONT_SIZE = 11
local BADGE_PADDING_X = 4
local BADGE_PADDING_Y = 2
local BADGE_CORNER_RADIUS = 3
local BADGE_GAP = 4
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
local debounceTimer = nil
local lastFilteredCount = 0

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
  AXTab = true,
  AXColorWell = true,
  AXDateField = true,
  AXTimeField = true,
  AXSearchField = true,
  AXSegmentedControl = true,
  AXMenuBarItem = true,
  AXDockItem = true,
}

-- Rows and cells are often clickable, but they are broad containers.
-- Keep them as low-priority fallbacks so they don't suppress specific controls.
local weakInteractiveRoles = {
  AXRow = true,
  AXCell = true,
  AXOutlineRow = true,
  AXImage = true,  -- often clickable in web views and toolbars
}

-- Maximum number of hints (prefix-free labels up to 3 chars)
local NUM_HINT_CHARS = #HINT_CHARS
local MAX_HINTS = NUM_HINT_CHARS * NUM_HINT_CHARS * NUM_HINT_CHARS
local MAX_CANDIDATES = MAX_HINTS

-- Generate prefix-free hint labels using a level-based strategy (from neru).
-- No label is a prefix of another, enabling unambiguous incremental matching.
-- Top-positioned elements get shorter (1-char) labels for faster access.
local function generateHints(count)
  local chars = {}
  for c in HINT_CHARS:gmatch(".") do
    table.insert(chars, c)
  end
  local numChars = #chars

  if count <= 0 then return {} end

  -- Determine how many labels to allocate at each length (level).
  -- Level 1 = single-char, level 2 = two-char, etc.
  -- Greedy: maximize short labels while ensuring enough capacity for the rest.
  local counts = {}
  local remaining = count
  local available = numChars

  while remaining > 0 do
    local nextCapacity = available * numChars
    local keep

    if available >= remaining then
      keep = remaining
    elseif nextCapacity < remaining then
      keep = 0
    else
      keep = math.floor((available * numChars - remaining) / (numChars - 1))
    end

    table.insert(counts, keep)
    remaining = remaining - keep
    available = (available - keep) * numChars

    if available == 0 and remaining > 0 then break end
  end

  local result = {}
  -- Tracks position in the base-N numbering system (0-based indices)
  local current = {}

  for level, keep in ipairs(counts) do
    if level == 1 then
      for i = 1, keep do
        table.insert(result, chars[i])
      end
      -- Two-char labels start with characters NOT used as single-char labels
      current = { keep } -- 0-based: first unused index
    else
      while #current < level do
        table.insert(current, 0)
      end

      for _ = 1, keep do
        local label = ""
        for _, idx in ipairs(current) do
          label = label .. chars[idx + 1] -- convert 0-based to 1-based Lua index
        end
        table.insert(result, label)

        -- Increment position (base-N with carry)
        for pos = #current, 1, -1 do
          current[pos] = current[pos] + 1
          if current[pos] < numChars then break end
          current[pos] = 0
        end
      end
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
  AXTable = true,
  AXOutline = true,
  AXList = true,
  AXBrowser = true,
  AXTabGroup = true,
  AXToolbar = true,
  AXRuler = true,
  AXRulerMarker = true,
  AXGrowArea = true,
  AXMatte = true,
}

local function getAttribute(element, name)
  local ok, value = pcall(function() return element:attributeValue(name) end)
  if ok then return value end
  return nil
end

local function getElementGeometry(element)
  local pos = getAttribute(element, "AXPosition")
  local size = getAttribute(element, "AXSize")
  if not pos or not size then return nil end

  return {
    position = pos,
    size = size,
    center = {
      x = pos.x + size.w / 2,
      y = pos.y + size.h / 2,
    },
    area = size.w * size.h,
  }
end

local function containsPoint(info, point)
  return point.x >= info.position.x
    and point.x <= info.position.x + info.size.w
    and point.y >= info.position.y
    and point.y <= info.position.y + info.size.h
end

local function intersectionArea(a, b)
  local left = math.max(a.x, b.x)
  local right = math.min(a.x + a.w, b.x + b.w)
  if right <= left then return 0 end

  local top = math.max(a.y, b.y)
  local bottom = math.min(a.y + a.h, b.y + b.h)
  if bottom <= top then return 0 end

  return (right - left) * (bottom - top)
end

local function overlapRatio(a, b)
  local overlap = intersectionArea(
    { x = a.position.x, y = a.position.y, w = a.size.w, h = a.size.h },
    { x = b.position.x, y = b.position.y, w = b.size.w, h = b.size.h }
  )
  if overlap == 0 then return 0 end
  return overlap / math.min(a.area, b.area)
end

local function getChildren(element)
  -- For tables and outlines, prefer AXVisibleRows to skip hidden/scrolled-out
  -- rows entirely. This avoids walking massive subtrees in long lists.
  local role = getAttribute(element, "AXRole")
  if role == "AXTable" or role == "AXOutline" then
    local visibleRows = getAttribute(element, "AXVisibleRows")
    if visibleRows and #visibleRows > 0 then return visibleRows end
  end

  local visibleChildren = getAttribute(element, "AXVisibleChildren")
  if visibleChildren and #visibleChildren > 0 then return visibleChildren end
  return getAttribute(element, "AXChildren")
end

local function getActionNames(element)
  local ok, actions = pcall(function() return element:actionNames() end)
  if ok then return actions end
  return nil
end

-- Check if an element is actionable and visible within the window frame
local function isActionable(element, windowFrame, geometry)
  local role = getAttribute(element, "AXRole")
  if not role then return nil end

  local enabled = getAttribute(element, "AXEnabled")
  if enabled == false then return nil end

  local info = geometry or getElementGeometry(element)
  if not info then return nil end
  if info.size.w < 5 or info.size.h < 5 then return nil end

  -- Must be within window bounds
  local cx = info.center.x
  local cy = info.center.y
  if cx < windowFrame.x or cx > windowFrame.x + windowFrame.w
    or cy < windowFrame.y or cy > windowFrame.y + windowFrame.h then
    return nil
  end

  -- Check if interactive by role
  if interactiveRoles[role] then
    info.role = role
    info.priority = 3
    return info
  end

  if weakInteractiveRoles[role] then
    info.role = role
    info.priority = 1
    return info
  end

  -- Skip action check for known non-interactive containers
  if skipActionCheckRoles[role] then return nil end

  -- For other roles (AXStaticText, AXImage, AXGroup, etc.),
  -- check if element exposes a press or open action
  local actions = getActionNames(element)
  if actions then
    for _, action in ipairs(actions) do
      if action == "AXPress" or action == "AXOpen" or action == "AXConfirm" or action == "AXShowMenu" then
        info.role = role
        info.priority = 2
        return info
      end
    end
  end

  return nil
end

-- Check if an element's bounds overlap the visible window area
-- Used to prune entire subtrees that are off-screen
local function isOnScreen(geometry, windowFrame)
  if not geometry then return true end -- assume visible if we can't tell

  -- Element is off-screen if it's entirely outside the window frame
  if geometry.position.x + geometry.size.w < windowFrame.x
    or geometry.position.x > windowFrame.x + windowFrame.w then
    return false
  end
  if geometry.position.y + geometry.size.h < windowFrame.y
    or geometry.position.y > windowFrame.y + windowFrame.h then
    return false
  end
  return true
end

local function filterCandidates(candidates)
  table.sort(candidates, function(a, b)
    if a.priority ~= b.priority then return a.priority > b.priority end
    if math.abs(a.area - b.area) > 1 then return a.area < b.area end
    if a.depth ~= b.depth then return a.depth > b.depth end
    if a.center.y ~= b.center.y then return a.center.y < b.center.y end
    return a.center.x < b.center.x
  end)

  local selected = {}
  for _, candidate in ipairs(candidates) do
    local redundant = false
    for _, existing in ipairs(selected) do
      local sameCenter = math.abs(candidate.center.x - existing.center.x) <= 4
        and math.abs(candidate.center.y - existing.center.y) <= 4
      if sameCenter or overlapRatio(candidate, existing) >= 0.85 then
        redundant = true
        break
      end
    end

    if not redundant then
      table.insert(selected, candidate)
    end
  end

  local final = {}
  for _, candidate in ipairs(selected) do
    local shadowed = false
    if candidate.priority == 1 then
      for _, other in ipairs(selected) do
        if other ~= candidate and other.priority > candidate.priority and containsPoint(candidate, other.center) then
          shadowed = true
          break
        end
      end
    end

    if not shadowed then
      table.insert(final, candidate)
    end
  end

  table.sort(final, function(a, b)
    local rowA = math.floor(a.center.y / 20)
    local rowB = math.floor(b.center.y / 20)
    if rowA ~= rowB then return rowA < rowB end
    return a.center.x < b.center.x
  end)

  while #final > MAX_HINTS do
    table.remove(final)
  end

  return final
end

-- Collect actionable elements using breadth-first search
-- BFS ensures even coverage across all areas of the window (toolbar, sidebar,
-- content) rather than exhausting one deep branch before visiting others
local function collectElements(axWin, winFrame)
  local deadlineNs = hs.timer.absoluteTime() + (WALK_DEADLINE_SECS * 1e9)
  local candidates = {}
  local visited = 0

  -- BFS queue entries: { element, depth, geometry }
  local queue = { { axWin, 0 } }
  local head = 1

  while head <= #queue do
    if #candidates >= MAX_CANDIDATES then break end

    -- Check wall-clock deadline periodically
    visited = visited + 1
    if visited % 40 == 0 then
      if hs.timer.absoluteTime() >= deadlineNs then break end
    end

    local entry = queue[head]
    head = head + 1
    local elem, depth, geometry = entry[1], entry[2], entry[3]

    if depth > MAX_DEPTH then goto continue end

    -- Check if this element is actionable
    if depth > 0 then -- skip root window element
      local info = isActionable(elem, winFrame, geometry)
      if info then
        info.element = elem
        info.depth = depth
        table.insert(candidates, info)
      end
    end

    -- Prefer visible children when available to avoid walking hidden subtrees.
    local children = getChildren(elem)
    if children then
      for _, child in ipairs(children) do
        local childGeometry = getElementGeometry(child)
        if isOnScreen(childGeometry, winFrame) then
          table.insert(queue, { child, depth + 1, childGeometry })
        end
      end
    end

    ::continue::
  end

  return filterCandidates(candidates)
end

local function clampBadgeFrame(frame, bw, bh, x, y)
  return {
    x = math.max(0, math.min(x, frame.w - bw)),
    y = math.max(0, math.min(y, frame.h - bh)),
    w = bw,
    h = bh,
  }
end

local function prefersInlineBadge(hint, bw, bh)
  if weakInteractiveRoles[hint.role or ""] then return true end
  return hint.size.w >= bw * 4 and hint.size.h <= bh * 2.5
end

local function chooseBadgeFrame(hint, frame, bw, bh, occupied)
  local anchors
  if prefersInlineBadge(hint, bw, bh) then
    anchors = {
      clampBadgeFrame(frame, bw, bh, hint.position.x - frame.x + BADGE_GAP, hint.center.y - frame.y - (bh / 2)),
      clampBadgeFrame(frame, bw, bh, hint.position.x + hint.size.w - bw - frame.x - BADGE_GAP, hint.center.y - frame.y - (bh / 2)),
      clampBadgeFrame(frame, bw, bh, hint.center.x - frame.x - (bw / 2), hint.center.y - frame.y - (bh / 2)),
      clampBadgeFrame(frame, bw, bh, hint.position.x - frame.x, hint.position.y - frame.y - bh - BADGE_GAP),
      clampBadgeFrame(frame, bw, bh, hint.position.x - frame.x, hint.position.y + hint.size.h - frame.y + BADGE_GAP),
    }
  else
    anchors = {
      clampBadgeFrame(frame, bw, bh, hint.position.x - frame.x, hint.position.y - frame.y - bh - BADGE_GAP),
      clampBadgeFrame(frame, bw, bh, hint.position.x + hint.size.w - bw - frame.x, hint.position.y - frame.y - bh - BADGE_GAP),
      clampBadgeFrame(frame, bw, bh, hint.position.x - frame.x + BADGE_GAP, hint.center.y - frame.y - (bh / 2)),
      clampBadgeFrame(frame, bw, bh, hint.position.x - frame.x, hint.position.y + hint.size.h - frame.y + BADGE_GAP),
      clampBadgeFrame(frame, bw, bh, hint.center.x - frame.x - (bw / 2), hint.center.y - frame.y - (bh / 2)),
    }
  end

  local bestFrame = anchors[1]
  local bestScore = math.huge
  for _, candidate in ipairs(anchors) do
    local score = 0
    for _, other in ipairs(occupied) do
      score = score + intersectionArea(candidate, other)
      if score >= bestScore then break end
    end

    if score < bestScore then
      bestFrame = candidate
      bestScore = score
      if score == 0 then break end
    end
  end

  return bestFrame
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
  local occupied = {}

  for _, hint in ipairs(hints) do
    local label = hint.label
    local isMatched = #inputBuffer > 0 and label:sub(1, #inputBuffer) == inputBuffer

    local textWidth = #label * charWidth
    local textHeight = BADGE_FONT_SIZE + 2
    local bw = textWidth + BADGE_PADDING_X * 2
    local bh = textHeight + BADGE_PADDING_Y * 2

    local badgeFrame = chooseBadgeFrame(hint, frame, bw, bh, occupied)
    local bx = badgeFrame.x
    local by = badgeFrame.y

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

    table.insert(occupied, badgeFrame)
  end

  hintCanvas:level("overlay")
  hintCanvas:behavior("canJoinAllSpaces")
  hintCanvas:clickActivating(false)
  hintCanvas:show()
end

-- Redraw overlay showing only hints that match the current input.
-- Uses count-based debounce heuristic from neru: when only the matched
-- prefix changed (same hint count), redraw immediately since only text
-- colors change (cheap). When the count changes (structural redraw),
-- debounce to avoid excessive canvas rebuilds during fast typing.
local function updateHints()
  if not screenFrame then return end

  local matching = {}
  for _, hint in ipairs(activeHints) do
    if hint.label:sub(1, #inputBuffer) == inputBuffer then
      table.insert(matching, hint)
    end
  end

  local newCount = #matching

  if debounceTimer then
    debounceTimer:stop()
    debounceTimer = nil
  end

  if newCount == lastFilteredCount then
    -- Only prefix colors changed — cheap redraw, do it immediately
    showHints(matching, screenFrame)
  else
    -- Structural change — debounce to batch rapid keystrokes
    local snapshot = matching
    debounceTimer = hs.timer.doAfter(0.04, function()
      debounceTimer = nil
      showHints(snapshot, screenFrame)
    end)
  end

  lastFilteredCount = newCount
end

-- Perform the action on the selected element.
-- Uses synthetic mouse click which is universally reliable across apps.
-- AXPress looks appealing but silently fails on many controls (terminal
-- tabs, browser elements, some buttons) — pcall returns true but nothing
-- happens, with no way to detect the failure.
local function activateElement(hint)
  local elem = hint.element
  local role = hint.role or ""

  -- Focus text inputs before clicking to place cursor
  if role == "AXTextField" or role == "AXTextArea" or role == "AXComboBox"
    or role == "AXSearchField" then
    pcall(function() elem:setAttributeValue("AXFocused", true) end)
  end

  -- Move mouse to target, brief settle, then click.
  -- The settle delay lets the target app recognize the cursor position
  -- (some apps highlight on hover before accepting clicks).
  local point = hs.geometry.point(hint.center.x, hint.center.y)
  hs.mouse.absolutePosition(point)
  hs.timer.usleep(30000) -- 30ms settle (neru uses similar post-move delay)
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
  lastFilteredCount = 0

  hideScanIndicator()

  if debounceTimer then
    debounceTimer:stop()
    debounceTimer = nil
  end

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

-- Collect menubar items as supplementary hint targets (inspired by neru).
-- These live outside the window frame, so we check against screenFrame.
local function collectMenubarElements(app, sFrame)
  local axApp = axuielement.applicationElement(app)
  if not axApp then return {} end

  local menuBar = getAttribute(axApp, "AXMenuBar")
  if not menuBar then return {} end

  local children = getAttribute(menuBar, "AXChildren")
  if not children then return {} end

  local candidates = {}
  for _, child in ipairs(children) do
    local info = isActionable(child, {
      x = sFrame.x, y = sFrame.y, w = sFrame.w, h = sFrame.h
    })
    if info then
      info.element = child
      info.depth = 1
      table.insert(candidates, info)
    end
  end

  return candidates
end

-- Core logic: walk the tree, build hints, show overlay
local function performScan(axWin, winFrame, app)
  if not isActive then return end

  hideScanIndicator()

  local elements = collectElements(axWin, winFrame)

  -- Merge menubar elements when enabled
  if SCAN_MENUBAR and app then
    local menubarElems = collectMenubarElements(app, screenFrame)
    for _, elem in ipairs(menubarElems) do
      table.insert(elements, elem)
    end
  end

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
    performScan(axWin, winFrame, app)
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
