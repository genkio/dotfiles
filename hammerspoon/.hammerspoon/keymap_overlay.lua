-- Keymap overlay: shows your whole Vial layout (every populated layer, stacked)
-- top-right. rcmd's rightCmd+x toggles it; the in-overlay "Load .vil" button
-- swaps the layout (copies your pick to config.vilPath).
--
-- A Bluetooth keyboard never reports its active layer to macOS, so the overlay
-- can't follow along live; it just shows all layers at once.

local M = {}

local webview = nil
local screenWatcher = nil
local cfg = nil

local state = {
  vilPath = nil,
  vilText = nil,
  data = nil,
  template = nil,
  populated = {},
  visible = false,
}

local DEFAULTS = {
  vilPath = "~/dotfiles/hammerspoon/.hammerspoon/keymap_overlay.vil",
  macroNames = { USER00 = "M0", USER01 = "M1", USER02 = "M2" },
  hideLayers = {},
  hideKeys = {},
  pickerDir = "~/Downloads",
  geometry = { margin = 12 },
  accent = "#7aa2f7",
  startHidden = true,
}

local function parentDirectory(path)
  return path:match("^(.*)/[^/]+$")
end

local function uniqueAppend(list, value)
  if not value then
    return
  end

  for _, existing in ipairs(list) do
    if existing == value then
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

local function resolveAsset(name)
  for _, directory in ipairs(sourceDirectories()) do
    local candidate = directory .. "/" .. name

    if hs.fs.attributes(candidate) then
      return candidate
    end
  end

  return nil
end

local function expandPath(path)
  if type(path) ~= "string" then
    return nil
  end

  if path:sub(1, 1) == "~" then
    return os.getenv("HOME") .. path:sub(2)
  end

  return path
end

local function notifyProblem(alertMessage, logMessage)
  hs.alert.show(alertMessage)
  print("-- keymap_overlay: " .. logMessage)
end

local function readFile(path)
  local file = io.open(path, "r")

  if not file then
    return nil
  end

  local contents = file:read("*a")
  file:close()
  return contents
end

local function deepMerge(base, override)
  for key, value in pairs(override) do
    if type(value) == "table" and type(base[key]) == "table" then
      deepMerge(base[key], value)
    else
      base[key] = value
    end
  end

  return base
end

local function loadConfig()
  for _, directory in ipairs(sourceDirectories()) do
    local path = directory .. "/keymap_overlay.config.lua"

    if hs.fs.attributes(path) then
      local ok, config = pcall(dofile, path)

      if ok and type(config) == "table" then
        return config
      end

      print("-- keymap_overlay: ignoring bad config " .. path)
    end
  end

  return nil
end

-- Ignore the 7th column (encoder push): it stays mapped even on empty layers,
-- so counting it would make every layer look populated.
local function computePopulated(data)
  local hidden = {}
  for _, layerNumber in ipairs(cfg.hideLayers or {}) do
    hidden[layerNumber] = true
  end

  local populated = {}

  for index, layer in ipairs(data.layout or {}) do
    local layerNumber = index - 1

    if not hidden[layerNumber] then
      local used = false

      for _, row in ipairs(layer) do
        for col = 1, 6 do
          local key = row[col]

          if key ~= nil and key ~= -1 and key ~= "KC_NO" then
            used = true
            break
          end
        end

        if used then
          break
        end
      end

      if used then
        table.insert(populated, layerNumber)
      end
    end
  end

  if #populated == 0 then
    table.insert(populated, 0)
  end

  return populated
end

local function buildHtml()
  local opts = {
    macroNames = cfg.macroNames,
    populated = state.populated,
    hideKeys = cfg.hideKeys,
    accent = cfg.accent,
  }

  local injection = ("window.KEYMAP_DATA = %s;\nwindow.KEYMAP_OPTS = %s;\n")
    :format(state.vilText, hs.json.encode(opts))

  return (state.template:gsub("/%*__DATA__%*/", function()
    return injection
  end))
end

local function fitWebview(width, height)
  if not webview then
    return
  end

  local frame = hs.screen.mainScreen():frame()
  local margin = cfg.geometry.margin
  local w = math.min(width, frame.w - margin * 2)
  local h = math.min(height, frame.h - margin * 2)

  webview:frame(hs.geometry.rect(frame.x + frame.w - w - margin, frame.y + margin, w, h))
end

-- A close-enough first size (refined to an exact fit by the webview's postSize
-- message) so the stack isn't clipped before that message lands.
local function initialRect()
  local frame = hs.screen.mainScreen():frame()
  local margin = cfg.geometry.margin
  local layers = math.max(#state.populated, 1)
  local height = math.min(70 + layers * 170, frame.h - margin * 2)

  return hs.geometry.rect(frame.x + frame.w - 480 - margin, frame.y + margin, 480, height)
end

local function basename(path)
  return path:match("[^/]+$") or path
end

local function shortPath(path)
  local home = os.getenv("HOME")

  if home and path:sub(1, #home) == home then
    return "~" .. path:sub(#home + 1)
  end

  return path
end

local function show()
  if not webview then
    return
  end

  webview:show()
  state.visible = true
end

local function hide()
  if not webview then
    return
  end

  webview:hide()
  state.visible = false
end

local function toggle()
  if state.visible then
    hide()
  else
    show()
  end
end

local function reloadVil(announce, force)
  local text = readFile(state.vilPath)

  if not force and text == state.vilText then
    if announce then
      hs.alert.show("keymap: no change")
    end

    return
  end

  local decoded = text and hs.json.decode(text)

  if type(decoded) ~= "table" or type(decoded.layout) ~= "table" then
    if announce then
      hs.alert.show("keymap: could not read .vil")
    end

    return
  end

  state.vilText = text
  state.data = decoded
  state.populated = computePopulated(decoded)

  if webview then
    webview:html(buildHtml())
  end

  if announce then
    hs.alert.show("keymap reloaded")
  end
end

local function normalizePickedPath(path)
  if path:sub(1, 7) == "file://" then
    return (path:sub(8):gsub("%%(%x%x)", function(hex)
      return string.char(tonumber(hex, 16))
    end))
  end

  return path
end

-- Explicit open panel; nothing loads unless you pick it. The pick is copied to
-- vilPath so the layout stays version-controlled in the repo.
local function pickVil()
  local choice = hs.dialog.chooseFileOrFolder(
    "Choose a Vial .vil layout",
    expandPath(cfg.pickerDir) or expandPath("~"),
    true,
    false,
    false,
    { "vil" },
    true
  )

  if not choice or not choice["1"] then
    return
  end

  local src = normalizePickedPath(choice["1"])
  local data = readFile(src)

  if not data then
    hs.alert.show("keymap: could not read " .. basename(src))
    return
  end

  if src ~= state.vilPath then
    local out = io.open(state.vilPath, "w")

    if not out then
      hs.alert.show("keymap: could not write " .. shortPath(state.vilPath))
      return
    end

    out:write(data)
    out:close()
  end

  reloadVil(false, true)
  hs.alert.show("keymap: loaded " .. basename(src))
end

local function createWebview()
  local controller = hs.webview.usercontent.new("keymap")
  controller:setCallback(function(message)
    local body = message.body

    if type(body) ~= "table" then
      return
    end

    if body.type == "pick" then
      pickVil()
    elseif tonumber(body.w) and tonumber(body.h) then
      fitWebview(tonumber(body.w), tonumber(body.h))
    end
  end)

  webview = hs.webview.new(initialRect(), { developerExtrasEnabled = false }, controller)
  webview:windowStyle({ "borderless", "nonactivating" })
  webview:transparent(true)
  webview:allowTextEntry(false)
  webview:shadow(false)
  webview:level(hs.canvas.windowLevels.floating)
  webview:behaviorAsLabels({ "canJoinAllSpaces", "stationary" })
  webview:html(buildHtml())
end

local function startWatchers()
  screenWatcher = hs.screen.watcher.new(function()
    if webview then
      local frame = webview:frame()
      fitWebview(frame.w, frame.h)
    end
  end)
  screenWatcher:start()
end

function M.stop()
  if screenWatcher then
    screenWatcher:stop()
    screenWatcher = nil
  end

  if webview then
    webview:delete()
    webview = nil
  end
end

function M.start()
  cfg = deepMerge(hs.fnutils.copy(DEFAULTS), loadConfig() or {})

  state.vilPath = expandPath(cfg.vilPath)

  if not state.vilPath or not hs.fs.attributes(state.vilPath) then
    state.vilPath = resolveAsset("keymap_overlay.vil")
  end

  if not state.vilPath then
    notifyProblem("keymap_overlay: no .vil found", "set config.vilPath to your Vial export")
    return false
  end

  local text = readFile(state.vilPath)
  local decoded = text and hs.json.decode(text)

  if type(decoded) ~= "table" or type(decoded.layout) ~= "table" then
    notifyProblem("keymap_overlay: bad .vil", "could not parse " .. state.vilPath)
    return false
  end

  state.template = resolveAsset("keymap_overlay.html")
  state.template = state.template and readFile(state.template)

  if not state.template then
    notifyProblem("keymap_overlay: missing keymap_overlay.html", "template not found")
    return false
  end

  state.vilText = text
  state.data = decoded
  state.populated = computePopulated(decoded)

  createWebview()
  startWatchers()

  if not cfg.startHidden then
    show()
  end

  return true
end

M.toggle = toggle

return M
