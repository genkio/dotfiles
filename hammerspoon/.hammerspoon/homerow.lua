-- Homerow: keyboard-driven navigation for macOS, inspired by homerow.app
--
-- HINT MODE (Ctrl+.) — Yellow labels appear on actionable UI elements
-- (buttons, links, text fields, list rows, tabs, etc.) in the focused
-- window. Type the hint characters to activate the target element.
--
-- SCROLL MODE (Ctrl+,) — Scroll the focused window with the keyboard.
-- If the focused window has multiple scrollable panes (e.g. a sidebar +
-- content list in a database app or IDE), a numbered picker appears
-- first — press 1/2/... to choose which pane to scroll. With a single
-- pane (or none), the cursor's current pane is used.
--   j / Down        scroll down            d            half page down
--   k / Up          scroll up              u            half page up
--   h / Left        scroll left            Space        full page down
--   l / Right       scroll right           Shift+Space  full page up
--   Shift+hjkl      faster scroll          g / G        top / bottom
--   Esc             exit (cancels picker, dismisses scroll mode)
--
-- How hint mode works:
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
-- The hint overlay auto-dismisses after DISMISS_TIMEOUT seconds.

local M = {}

local axuielement = require("hs.axuielement")
local canvas = require("hs.canvas")
local eventtap = require("hs.eventtap")

-- Configuration
local HINT_CHARS = "asdfjklgh"
local TRIGGER_MODS = { "ctrl" }
local TRIGGER_KEY = "."
local SCROLL_TRIGGER_KEY = ","
local DISMISS_TIMEOUT = 15
local MAX_DEPTH = 30
local WALK_DEADLINE_SECS = 1.5
local SCAN_MENUBAR = true

-- Scroll mode tuning
local SCROLL_STEP_PX = 60        -- per j/k or arrow press
local SCROLL_DASH_MULTIPLIER = 4 -- Shift+hjkl scrolls this much further
local SCROLL_HALF_PAGE_RATIO = 0.5 -- d/u: window-height fraction
local SCROLL_EDGE_PX = 100000    -- g/G: large enough that apps clamp at edge

-- Visual style
local BADGE_BG = { red = 1.0, green = 0.80, blue = 0.0, alpha = 0.95 }
local BADGE_BORDER = { red = 0.85, green = 0.65, blue = 0.0, alpha = 0.85 }
local BADGE_TEXT_COLOR = { red = 0.08, green = 0.08, blue = 0.08, alpha = 1 }
local BADGE_FONT_NAME = "Menlo-Bold"
local BADGE_FONT_SIZE = 10
local BADGE_PADDING_X = 4
local BADGE_PADDING_Y = 2
local BADGE_CORNER_RADIUS = 3
local BADGE_GAP = 3
local ARROW_SIZE = 3
local BADGE_OUTSIDE_GAP = BADGE_GAP + ARROW_SIZE + 2
local DIM_OVERLAY_COLOR = { white = 0, alpha = 0.10 }
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

-- Scroll mode state
local scrollHotkey = nil
local scrollKeyTap = nil
local scrollIndicator = nil
local scrollActive = false

-- Scroll-area picker state (shown when window has 2+ scroll areas)
local scrollPickCanvas = nil
local scrollPickKeyTap = nil
local scrollPickAreas = nil
local scrollPicking = false

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

local rowLikeRoles = {
  AXRow = true,
  AXCell = true,
  AXOutlineRow = true,
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
  local role = getAttribute(element, "AXRole")

  -- For tables and outlines, prefer AXVisibleRows to skip hidden/scrolled-out
  -- rows entirely. This avoids walking massive subtrees in long lists.
  if role == "AXTable" or role == "AXOutline" then
    local visibleRows = getAttribute(element, "AXVisibleRows")
    if visibleRows and #visibleRows > 0 then return visibleRows end
  end

  -- AXVisibleChildren is reliable for scrollable views, but unreliable for
  -- generic containers: Chromium-based browsers in fullscreen mode return
  -- only the focused content area on the window's AXVisibleChildren,
  -- silently dropping the toolbar and bookmark bar subtrees. For everything
  -- except scroll areas, walk AXChildren and let isOnScreen() prune what's
  -- actually off-screen.
  if role == "AXScrollArea" then
    local visibleChildren = getAttribute(element, "AXVisibleChildren")
    if visibleChildren and #visibleChildren > 0 then return visibleChildren end
  end

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

  -- Collapse weak interactive elements that share a visual row.
  -- In table/list views, AXRow/AXCell/AXOutlineRow siblings sit side-by-side
  -- so they survive overlap-based dedup. Keep only one label per visual row
  -- for these low-priority elements (matches Homerow app behavior).
  local deduped = {}
  for _, candidate in ipairs(final) do
    if candidate.priority <= 1 then
      local hasSameRowPeer = false
      for _, existing in ipairs(deduped) do
        if existing.priority <= 1
          and math.abs(candidate.center.y - existing.center.y) <= 6 then
          hasSameRowPeer = true
          break
        end
      end
      if not hasSameRowPeer then
        table.insert(deduped, candidate)
      end
    else
      table.insert(deduped, candidate)
    end
  end

  while #deduped > MAX_HINTS do
    table.remove(deduped)
  end

  return deduped
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

    -- Walk into each child whose geometry overlaps the window frame.
    -- isOnScreen() prunes off-screen subtrees so we don't waste time on
    -- elements the user can't see.
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

local function prefersLeadingEdgeBadge(hint, bw, bh)
  if rowLikeRoles[hint.role or ""] then return false end
  if weakInteractiveRoles[hint.role or ""] then return true end
  return hint.size.w >= bw * 4 and hint.size.h <= bh * 2.5
end

local function getBadgeTargetFrame(hint, frame)
  local targetFrame = {
    x = hint.position.x - frame.x,
    y = hint.position.y - frame.y,
    w = hint.size.w,
    h = hint.size.h,
  }

  if not rowLikeRoles[hint.role or ""] then
    return targetFrame
  end

  -- AX rows/cells span the entire list width, but the visually meaningful
  -- click target is usually around the row's content line. Use a narrower,
  -- centered band for badge placement so hints sit near Homerow.app's
  -- placement instead of piling onto the filename edge.
  local placementWidth = math.min(targetFrame.w, math.max(160, math.min(targetFrame.w * 0.35, 260)))
  local placementHeight = math.min(targetFrame.h, math.max(12, math.min(targetFrame.h * 0.45, 18)))

  return {
    x = targetFrame.x + ((targetFrame.w - placementWidth) / 2),
    y = targetFrame.y + ((targetFrame.h - placementHeight) / 2),
    w = placementWidth,
    h = placementHeight,
  }
end

local function makeBadgeCandidate(frame, bw, bh, x, y, rank)
  local badgeFrame = clampBadgeFrame(frame, bw, bh, x, y)
  badgeFrame.rank = rank
  badgeFrame.clampDistance = math.abs(badgeFrame.x - x) + math.abs(badgeFrame.y - y)
  return badgeFrame
end

local function chooseBadgeFrame(hint, frame, bw, bh, occupied, hints)
  local targetFrame = hint.badgeTargetFrame or getBadgeTargetFrame(hint, frame)
  local targetCenterX = targetFrame.x + (targetFrame.w / 2)
  local targetCenterY = targetFrame.y + (targetFrame.h / 2)
  local targetRight = targetFrame.x + targetFrame.w
  local targetBottom = targetFrame.y + targetFrame.h
  local otherTargetPenalty = rowLikeRoles[hint.role or ""] and 150 or 5000

  local primaryX
  local secondaryX
  local tertiaryX
  if prefersLeadingEdgeBadge(hint, bw, bh) then
    primaryX = targetFrame.x + BADGE_GAP
    secondaryX = targetCenterX - (bw / 2)
    tertiaryX = targetRight - bw - BADGE_GAP
  else
    primaryX = targetCenterX - (bw / 2)
    secondaryX = targetFrame.x + BADGE_GAP
    tertiaryX = targetRight - bw - BADGE_GAP
  end

  local candidates = {
    makeBadgeCandidate(frame, bw, bh, primaryX, targetBottom + BADGE_OUTSIDE_GAP, 1),
    makeBadgeCandidate(frame, bw, bh, secondaryX, targetBottom + BADGE_OUTSIDE_GAP, 2),
    makeBadgeCandidate(frame, bw, bh, tertiaryX, targetBottom + BADGE_OUTSIDE_GAP, 3),
    makeBadgeCandidate(frame, bw, bh, primaryX, targetFrame.y - bh - BADGE_OUTSIDE_GAP, 4),
    makeBadgeCandidate(frame, bw, bh, secondaryX, targetFrame.y - bh - BADGE_OUTSIDE_GAP, 5),
    makeBadgeCandidate(frame, bw, bh, tertiaryX, targetFrame.y - bh - BADGE_OUTSIDE_GAP, 6),
    makeBadgeCandidate(frame, bw, bh, targetRight + BADGE_OUTSIDE_GAP, targetCenterY - (bh / 2), 7),
    makeBadgeCandidate(frame, bw, bh, targetFrame.x - bw - BADGE_OUTSIDE_GAP, targetCenterY - (bh / 2), 8),
  }

  local bestFrame = candidates[1]
  local bestScore = math.huge
  for _, candidate in ipairs(candidates) do
    local occupiedOverlap = 0
    for _, other in ipairs(occupied) do
      occupiedOverlap = occupiedOverlap + intersectionArea(candidate, other)
      if occupiedOverlap >= bestScore then break end
    end

    local targetOverlap = intersectionArea(candidate, targetFrame)
    local otherTargetOverlap = 0
    for _, other in ipairs(hints) do
      if other ~= hint then
        local otherFrame = other.badgeTargetFrame or getBadgeTargetFrame(other, frame)
        otherTargetOverlap = otherTargetOverlap + intersectionArea(candidate, otherFrame)
        if otherTargetOverlap > 0 and (targetOverlap * 1000000) + (otherTargetOverlap * otherTargetPenalty) >= bestScore then
          break
        end
      end
    end

    local badgeCenterX = candidate.x + (candidate.w / 2)
    local badgeCenterY = candidate.y + (candidate.h / 2)
    local targetDistance = math.abs(badgeCenterX - targetCenterX) + math.abs(badgeCenterY - targetCenterY)
    local score = (targetOverlap * 1000000)
      + (otherTargetOverlap * otherTargetPenalty)
      + (occupiedOverlap * 1000)
      + (candidate.rank * 100)
      + (candidate.clampDistance * 10)
      + targetDistance

    if score < bestScore then
      bestFrame = candidate
      bestScore = score
      if targetOverlap == 0 and otherTargetOverlap == 0 and occupiedOverlap == 0 and candidate.clampDistance == 0 then
        break
      end
    end
  end

  return bestFrame
end

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

local function buildArrowGeometry(hint, frame, badgeFrame)
  local targetFrame = hint.badgeTargetFrame or getBadgeTargetFrame(hint, frame)
  local targetCenterX = targetFrame.x + (targetFrame.w / 2)
  local targetCenterY = targetFrame.y + (targetFrame.h / 2)
  local targetRight = targetFrame.x + targetFrame.w
  local targetBottom = targetFrame.y + targetFrame.h

  local bx = badgeFrame.x
  local by = badgeFrame.y
  local bw = badgeFrame.w
  local bh = badgeFrame.h
  local badgeRight = bx + bw
  local badgeBottom = by + bh
  local edgeInset = BADGE_CORNER_RADIUS + ARROW_SIZE + 1

  if by >= targetBottom then
    local arrowX = clamp(targetCenterX, bx + edgeInset, badgeRight - edgeInset)
    return {
      { x = arrowX - ARROW_SIZE, y = by + 0.5 },
      { x = arrowX + ARROW_SIZE, y = by + 0.5 },
      { x = arrowX, y = by - ARROW_SIZE },
    }, {
      { x = arrowX - ARROW_SIZE, y = by },
      { x = arrowX, y = by - ARROW_SIZE },
      { x = arrowX + ARROW_SIZE, y = by },
    }
  end

  if badgeBottom <= targetFrame.y then
    local arrowX = clamp(targetCenterX, bx + edgeInset, badgeRight - edgeInset)
    return {
      { x = arrowX - ARROW_SIZE, y = badgeBottom - 0.5 },
      { x = arrowX + ARROW_SIZE, y = badgeBottom - 0.5 },
      { x = arrowX, y = badgeBottom + ARROW_SIZE },
    }, {
      { x = arrowX - ARROW_SIZE, y = badgeBottom },
      { x = arrowX, y = badgeBottom + ARROW_SIZE },
      { x = arrowX + ARROW_SIZE, y = badgeBottom },
    }
  end

  if bx >= targetRight then
    local arrowY = clamp(targetCenterY, by + edgeInset, badgeBottom - edgeInset)
    return {
      { x = bx + 0.5, y = arrowY - ARROW_SIZE },
      { x = bx + 0.5, y = arrowY + ARROW_SIZE },
      { x = bx - ARROW_SIZE, y = arrowY },
    }, {
      { x = bx, y = arrowY - ARROW_SIZE },
      { x = bx - ARROW_SIZE, y = arrowY },
      { x = bx, y = arrowY + ARROW_SIZE },
    }
  end

  if badgeRight <= targetFrame.x then
    local arrowY = clamp(targetCenterY, by + edgeInset, badgeBottom - edgeInset)
    return {
      { x = badgeRight - 0.5, y = arrowY - ARROW_SIZE },
      { x = badgeRight - 0.5, y = arrowY + ARROW_SIZE },
      { x = badgeRight + ARROW_SIZE, y = arrowY },
    }, {
      { x = badgeRight, y = arrowY - ARROW_SIZE },
      { x = badgeRight + ARROW_SIZE, y = arrowY },
      { x = badgeRight, y = arrowY + ARROW_SIZE },
    }
  end

  return nil, nil
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
    hint.badgeTargetFrame = getBadgeTargetFrame(hint, frame)
  end

  for _, hint in ipairs(hints) do
    local label = hint.label
    local isMatched = #inputBuffer > 0 and label:sub(1, #inputBuffer) == inputBuffer

    local textWidth = #label * charWidth
    local textHeight = BADGE_FONT_SIZE + 2
    local bw = textWidth + BADGE_PADDING_X * 2
    local bh = textHeight + BADGE_PADDING_Y * 2

    local badgeFrame = chooseBadgeFrame(hint, frame, bw, bh, occupied, hints)
    local bx = badgeFrame.x
    local by = badgeFrame.y

    local bgColor = isMatched and MATCHED_BG or BADGE_BG
    local borderColor = isMatched and MATCHED_BORDER or BADGE_BORDER
    local textColor = isMatched and MATCHED_TEXT_COLOR or BADGE_TEXT_COLOR

    local arrowFill, arrowBorder = buildArrowGeometry(hint, frame, badgeFrame)

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

    if arrowFill then
      -- Filled triangle (seamlessly connects to badge body)
      hintCanvas:insertElement({
        type = "segments",
        closed = true,
        action = "fill",
        fillColor = bgColor,
        coordinates = arrowFill,
      })
      -- Border on the two exposed edges only (open path, no base line)
      hintCanvas:insertElement({
        type = "segments",
        closed = false,
        action = "stroke",
        strokeColor = borderColor,
        strokeWidth = 1,
        coordinates = arrowBorder,
      })
    end

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

local function isScreenshotShortcut(event)
  local flags = event:getFlags()
  if not flags.cmd or not flags.shift then return false end

  local keyCode = event:getKeyCode()
  return keyCode == hs.keycodes.map["3"]
    or keyCode == hs.keycodes.map["4"]
    or keyCode == hs.keycodes.map["5"]
end

-- Start the key capture event tap for hint selection
local function startKeyTap()
  keyTap = eventtap.new({ eventtap.event.types.keyDown }, function(event)
    local keyCode = event:getKeyCode()
    local char = (event:getCharacters() or ""):lower()

    -- Let macOS screenshot shortcuts pass through so the overlay stays visible
    if isScreenshotShortcut(event) then
      return false
    end

    -- Escape always dismisses, regardless of modifiers.
    if keyCode == 53 then
      exitHintMode()
      return true
    end

    -- Modifier combos: dismiss hint mode and let the system handle the
    -- shortcut (Cmd+W, Cmd+Q, Cmd+Tab, etc.). The exception is our own
    -- trigger (Ctrl+.) — pressing it again should be a clean dismissal,
    -- not dismiss-and-immediately-re-enter via the hotkey.
    local flags = event:getFlags()
    if flags.cmd or flags.ctrl or flags.alt then
      exitHintMode()
      if flags.ctrl and not flags.cmd and not flags.alt and char == "." then
        return true
      end
      return false
    end

    -- Backspace: remove last character
    if keyCode == 51 then
      if #inputBuffer > 0 then
        inputBuffer = inputBuffer:sub(1, -2)
        updateHints()
      end
      return true
    end

    -- Ignore empty or non-hint characters. The empty-string check matters:
    -- string.find("", "", 1, true) returns (1, 0) which is truthy, so without
    -- this guard a keystroke that produces no character would be silently
    -- consumed as if it were a hint match.
    if char == "" or not HINT_CHARS:find(char, 1, true) then
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
    exitHintMode()
    return
  end

  -- The AX walk above can take hundreds of milliseconds; the user may have
  -- pressed Esc or re-triggered hint mode while we were busy. Bail before
  -- mutating UI state so we don't paint a "ghost" overlay into a dismissed
  -- mode (canvas + keytap with isActive == false).
  if not isActive then return end

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

-- Scroll mode --------------------------------------------------------------
-- Continuous keyboard scrolling for the focused window.
--
-- On entry we walk the AX tree to find scrollable regions (AXScrollArea):
--   0 areas — fall through to "scroll under cursor" (the cursor is the
--             hit-test target for synthetic CGEvent scroll wheels).
--   1 area  — nudge the cursor into that area if it isn't there already,
--             then enter scroll mode. Single area is unambiguous.
--   2+      — show a numbered picker over each pane. After the user picks,
--             move the cursor into that pane and start scroll mode.
--
-- Scrolling itself is implemented via synthetic scroll-wheel events posted
-- at the current cursor position, so apps receive them through their normal
-- event-handling path — works for web views, native lists, terminals, etc.

local function findScrollAreas(axWin, winFrame)
  -- Bounded BFS — we usually find scroll areas within the first couple of
  -- AX-tree levels (toolbar, sidebar, content). Cap on time so an
  -- unexpectedly deep tree never stalls Ctrl+,.
  local deadlineNs = hs.timer.absoluteTime() + (0.5 * 1e9)
  local areas = {}
  local queue = { axWin }
  local head = 1
  local visited = 0

  while head <= #queue and #areas < 9 do
    visited = visited + 1
    if visited % 40 == 0 and hs.timer.absoluteTime() >= deadlineNs then
      break
    end

    local elem = queue[head]
    head = head + 1

    local role = getAttribute(elem, "AXRole")

    if role == "AXScrollArea" then
      local geometry = getElementGeometry(elem)
      -- Filter out tiny scroll areas (e.g. menu/toolbar overflow scrollers).
      -- 100×100 keeps real content panes while excluding chrome.
      if geometry and geometry.size.w >= 100 and geometry.size.h >= 100
         and isOnScreen(geometry, winFrame) then
        table.insert(areas, { element = elem, geometry = geometry })
      end
      -- Don't descend: nested scroll areas are rare and the inner one
      -- almost always represents the same target.
    else
      local children = getAttribute(elem, "AXChildren")
      if children then
        for _, child in ipairs(children) do
          local childGeom = getElementGeometry(child)
          if isOnScreen(childGeom, winFrame) then
            table.insert(queue, child)
          end
        end
      end
    end
  end

  -- Reading order: top-to-bottom, then left-to-right. So in a sidebar +
  -- content layout the sidebar is "1" and the content pane is "2".
  table.sort(areas, function(a, b)
    local rowA = math.floor(a.geometry.center.y / 50)
    local rowB = math.floor(b.geometry.center.y / 50)
    if rowA ~= rowB then return rowA < rowB end
    return a.geometry.center.x < b.geometry.center.x
  end)

  return areas
end

local function getScrollHalfPage()
  local app = hs.application.frontmostApplication()
  local win = app and app:focusedWindow()
  if win then return math.max(80, win:frame().h * SCROLL_HALF_PAGE_RATIO) end
  return 400
end

local function postScroll(dx, dy)
  -- macOS natural scrolling inverts wheel direction at the input layer.
  -- Invert here so j always moves *down through content* regardless of
  -- the user's preference. Flip this branch if it feels backwards.
  if hs.mouse.scrollDirection() == "natural" then
    dx, dy = -dx, -dy
  end
  eventtap.event.newScrollEvent({ dx, dy }, {}, "pixel"):post()
end

local function moveCursorIntoArea(area)
  -- Only relocate the cursor if it isn't already inside the chosen area —
  -- a needless jump is jarring for users who already had the cursor parked
  -- in the right pane.
  local pos = hs.mouse.absolutePosition()
  local geom = area.geometry
  if pos.x >= geom.position.x and pos.x <= geom.position.x + geom.size.w
    and pos.y >= geom.position.y and pos.y <= geom.position.y + geom.size.h then
    return
  end
  hs.mouse.absolutePosition(hs.geometry.point(geom.center.x, geom.center.y))
end

local function showScrollIndicator()
  if scrollIndicator then scrollIndicator:delete() end

  local app = hs.application.frontmostApplication()
  local win = app and app:focusedWindow()
  local screen = (win and win:screen()) or hs.screen.mainScreen()
  local sFrame = screen:frame()

  local label = "SCROLL"
  local charW = BADGE_FONT_SIZE * 0.65
  local w = math.floor(#label * charW + BADGE_PADDING_X * 2 + 2)
  local h = BADGE_FONT_SIZE + 2 + BADGE_PADDING_Y * 2
  local x = sFrame.x + sFrame.w - w - 12
  local y = sFrame.y + 8

  scrollIndicator = canvas.new({ x = x, y = y, w = w, h = h })
  scrollIndicator:insertElement({
    type = "rectangle",
    fillColor = BADGE_BG,
    strokeColor = BADGE_BORDER,
    strokeWidth = 1,
    roundedRectRadii = { xRadius = BADGE_CORNER_RADIUS, yRadius = BADGE_CORNER_RADIUS },
    frame = { x = 0, y = 0, w = w, h = h },
  })
  scrollIndicator:insertElement({
    type = "text",
    text = label,
    textColor = BADGE_TEXT_COLOR,
    textFont = BADGE_FONT_NAME,
    textSize = BADGE_FONT_SIZE,
    textAlignment = "center",
    frame = { x = 0, y = BADGE_PADDING_Y - 1, w = w, h = h - BADGE_PADDING_Y },
  })
  scrollIndicator:level("overlay")
  scrollIndicator:behavior("canJoinAllSpaces")
  scrollIndicator:clickActivating(false)
  scrollIndicator:show()
end

local function hideScrollIndicator()
  if scrollIndicator then
    scrollIndicator:delete()
    scrollIndicator = nil
  end
end

local function exitScrollMode()
  scrollActive = false
  hideScrollIndicator()
  if scrollKeyTap then
    scrollKeyTap:stop()
    scrollKeyTap = nil
  end
end

local function exitScrollAreaPicker()
  scrollPicking = false
  scrollPickAreas = nil
  if scrollPickCanvas then
    scrollPickCanvas:delete()
    scrollPickCanvas = nil
  end
  if scrollPickKeyTap then
    scrollPickKeyTap:stop()
    scrollPickKeyTap = nil
  end
end

local function handleScrollKey(event)
  local keyCode = event:getKeyCode()
  local char = (event:getCharacters() or ""):lower()
  local flags = event:getFlags()

  -- Esc: clean exit
  if keyCode == 53 then
    exitScrollMode()
    return true
  end

  -- Cmd/Ctrl/Alt combos: pass through and exit so app shortcuts still work
  -- (e.g. Cmd+Tab to switch apps, Cmd+W to close a tab). Special-case our
  -- own trigger (Ctrl+,) — consume it so the hotkey doesn't immediately
  -- re-enter scroll mode, which would feel like a broken toggle.
  if flags.cmd or flags.ctrl or flags.alt then
    exitScrollMode()
    if flags.ctrl and not flags.cmd and not flags.alt and char == "," then
      return true
    end
    return false
  end

  local stepMul = flags.shift and SCROLL_DASH_MULTIPLIER or 1
  local step = SCROLL_STEP_PX * stepMul

  -- Vertical
  if char == "j" or keyCode == hs.keycodes.map["down"] then
    postScroll(0, -step)
    return true
  end
  if char == "k" or keyCode == hs.keycodes.map["up"] then
    postScroll(0, step)
    return true
  end

  -- Horizontal
  if char == "h" or keyCode == hs.keycodes.map["left"] then
    postScroll(-step, 0)
    return true
  end
  if char == "l" or keyCode == hs.keycodes.map["right"] then
    postScroll(step, 0)
    return true
  end

  -- Half-page (d/u) and full-page (Space / Shift+Space)
  if char == "d" then
    postScroll(0, -getScrollHalfPage())
    return true
  end
  if char == "u" then
    postScroll(0, getScrollHalfPage())
    return true
  end
  if keyCode == hs.keycodes.map["space"] then
    local page = getScrollHalfPage() * 2
    postScroll(0, flags.shift and page or -page)
    return true
  end

  -- g / G: top / bottom. Send a delta large enough that any reasonable
  -- scroll view clamps at its content edge.
  if char == "g" then
    postScroll(0, flags.shift and -SCROLL_EDGE_PX or SCROLL_EDGE_PX)
    return true
  end

  -- Anything else: exit and consume (matches hint mode's behavior).
  exitScrollMode()
  return true
end

local function startScrollKeyTap()
  -- Defensive: if a previous keytap is still around (e.g. a deferred call
  -- from the picker fired after the user re-entered scroll mode another
  -- way), stop it before we replace it. Otherwise both taps would intercept
  -- keystrokes and the old one leaks.
  if scrollKeyTap then
    scrollKeyTap:stop()
    scrollKeyTap = nil
  end
  scrollActive = true
  showScrollIndicator()
  scrollKeyTap = eventtap.new({ eventtap.event.types.keyDown }, handleScrollKey)
  scrollKeyTap:start()
end

local function handleScrollPickKey(event)
  local keyCode = event:getKeyCode()
  local char = event:getCharacters() or ""
  local flags = event:getFlags()

  -- Esc: cancel without entering scroll mode
  if keyCode == 53 then
    exitScrollAreaPicker()
    return true
  end

  -- Cmd/Ctrl/Alt combos: cancel and pass through so app shortcuts (Cmd+Tab,
  -- Cmd+W, etc.) keep working if the user reflexively reaches for one.
  -- Special-case our own trigger (Ctrl+,) so it cleanly dismisses the picker
  -- instead of bouncing back to a fresh picker through the hotkey.
  if flags.cmd or flags.ctrl or flags.alt then
    exitScrollAreaPicker()
    if flags.ctrl and not flags.cmd and not flags.alt and char == "," then
      return true
    end
    return false
  end

  -- Digit keys 1-9 select the matching area
  local idx = tonumber(char)
  if idx and scrollPickAreas and idx >= 1 and idx <= #scrollPickAreas then
    local area = scrollPickAreas[idx]
    exitScrollAreaPicker()
    moveCursorIntoArea(area)
    -- Defer one run-loop tick so the picker overlay is fully gone before
    -- the SCROLL indicator appears (avoids a brief flash of both visible).
    hs.timer.doAfter(0.02, startScrollKeyTap)
    return true
  end

  -- Anything else: cancel and consume (matches hint-mode dismissal)
  exitScrollAreaPicker()
  return true
end

local function showScrollAreaPicker(areas, screen)
  if scrollPickCanvas then scrollPickCanvas:delete() end

  local sFrame = screen:fullFrame()
  scrollPickAreas = areas
  scrollPicking = true

  scrollPickCanvas = canvas.new(sFrame)

  -- Dim background to focus attention on the numbered badges, mirroring
  -- the hint-mode overlay treatment.
  scrollPickCanvas:insertElement({
    type = "rectangle",
    fillColor = DIM_OVERLAY_COLOR,
    strokeColor = { alpha = 0 },
    frame = { x = 0, y = 0, w = sFrame.w, h = sFrame.h },
  })

  -- Bigger labels than hint badges — picker is a coarse, decisive choice
  -- (one of a few panes) and these get centered in spacious panes.
  local fontSize = 18
  local charW = fontSize * 0.65

  for i, area in ipairs(areas) do
    local label = tostring(i)
    local cx = area.geometry.center.x - sFrame.x
    local cy = area.geometry.center.y - sFrame.y
    local w = math.floor(#label * charW + 14)
    local h = fontSize + 8

    scrollPickCanvas:insertElement({
      type = "rectangle",
      fillColor = BADGE_BG,
      strokeColor = BADGE_BORDER,
      strokeWidth = 1.5,
      roundedRectRadii = { xRadius = 6, yRadius = 6 },
      frame = { x = cx - w / 2, y = cy - h / 2, w = w, h = h },
    })
    scrollPickCanvas:insertElement({
      type = "text",
      text = label,
      textColor = BADGE_TEXT_COLOR,
      textFont = BADGE_FONT_NAME,
      textSize = fontSize,
      textAlignment = "center",
      frame = { x = cx - w / 2, y = cy - h / 2 + 2, w = w, h = h - 2 },
    })
  end

  scrollPickCanvas:level("overlay")
  scrollPickCanvas:behavior("canJoinAllSpaces")
  scrollPickCanvas:clickActivating(false)
  scrollPickCanvas:show()

  scrollPickKeyTap = eventtap.new({ eventtap.event.types.keyDown }, handleScrollPickKey)
  scrollPickKeyTap:start()
end

local function enterScrollMode()
  if scrollActive then
    exitScrollMode()
    return
  end
  if scrollPicking then
    exitScrollAreaPicker()
    return
  end

  -- If hint mode happens to be live, dismiss it first so the two modes
  -- never fight over keystrokes.
  if isActive then exitHintMode() end

  -- Walk AX tree of the focused window for scroll areas. If we find more
  -- than one, the user is in a multi-pane app (database GUI, IDE, mail
  -- client) and we present a numbered picker. Otherwise behavior matches
  -- a single-pane app — scroll wherever the cursor sits.
  local app = hs.application.frontmostApplication()
  local win = app and app:focusedWindow()

  if win then
    local axWin = axuielement.windowElement(win)
    if axWin then
      local areas = findScrollAreas(axWin, win:frame())
      if #areas >= 2 then
        local screen = win:screen() or hs.screen.mainScreen()
        showScrollAreaPicker(areas, screen)
        return
      elseif #areas == 1 then
        moveCursorIntoArea(areas[1])
      end
    end
  end

  startScrollKeyTap()
end

function M.start()
  hotkey = hs.hotkey.bind(TRIGGER_MODS, TRIGGER_KEY, enterHintMode)
  scrollHotkey = hs.hotkey.bind(TRIGGER_MODS, SCROLL_TRIGGER_KEY, enterScrollMode)
  return true
end

function M.stop()
  exitHintMode()
  exitScrollMode()
  exitScrollAreaPicker()
  if hotkey then
    hotkey:delete()
    hotkey = nil
  end
  if scrollHotkey then
    scrollHotkey:delete()
    scrollHotkey = nil
  end
end

return M
