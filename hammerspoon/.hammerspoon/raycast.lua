-- Raycast-lite: option-Space command palette for Shortcuts and quick links.
--
-- Features:
--   - Search and run Apple Shortcuts from the Shortcuts app
--   - Quick links from raycast.config.lua with {argument}, {query}, or {id}
--   - Type a search directly, then pick a quick link to open it

local M = {}

local chooser = nil
local launcherHotkey = nil
local currentQuickLinks = {}
local shortcutsCache = nil
local shortcutsCacheTime = 0
local shortcutsCacheTtl = 60
local shortcutListErrorShown = false
local runningTasks = {}

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
    uniqueAppend(candidates, directory .. "/raycast.config.lua")
  end

  return candidates
end

local function notifyConfigProblem(alertMessage, logMessage)
  hs.alert.show(alertMessage)
  print("-- raycast-lite: " .. logMessage)
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

  return nil, "create raycast.config.lua next to raycast.lua or in " .. hs.configdir
end

local function normalizeQuickLinks(config)
  if type(config) ~= "table" then
    return nil, "raycast.config.lua must return a table"
  end

  local quickLinks = config.quickLinks

  if type(quickLinks) ~= "table" then
    return nil, "raycast.config.lua must define quickLinks"
  end

  local normalized = {}

  for index, quickLink in ipairs(quickLinks) do
    if type(quickLink) ~= "table" then
      return nil, ("quickLinks[%d] must be a table"):format(index)
    end

    if type(quickLink.name) ~= "string" or quickLink.name == "" then
      return nil, ("quickLinks[%d].name must be a non-empty string"):format(index)
    end

    if type(quickLink.link) ~= "string" or quickLink.link == "" then
      return nil, ("quickLinks[%d].link must be a non-empty string"):format(index)
    end

    table.insert(normalized, {
      name = quickLink.name,
      link = quickLink.link,
      iconName = quickLink.iconName,
    })
  end

  return normalized
end

local function trim(value)
  if type(value) ~= "string" then
    return ""
  end

  return value:match("^%s*(.-)%s*$") or ""
end

local function matchesQuery(text, query)
  query = trim(query):lower()

  if query == "" then
    return true
  end

  text = tostring(text or ""):lower()

  for token in query:gmatch("%S+") do
    if not text:find(token, 1, true) then
      return false
    end
  end

  return true
end

local function encodeUrlComponent(value)
  value = tostring(value or "")
  value = value:gsub("\n", " ")

  return value:gsub("([^%w%-_%.~])", function(character)
    return ("%%%02X"):format(string.byte(character))
  end)
end

local function quickLinkRequiresArgument(quickLink)
  return quickLink.link:find("{argument}", 1, true) ~= nil
    or quickLink.link:find("{query}", 1, true) ~= nil
    or quickLink.link:find("{id}", 1, true) ~= nil
end

local function firstWord(value)
  return tostring(value or ""):match("^%s*(%S+)") or "query"
end

local function quickLinkInputHint(quickLink)
  return ("%s <input>"):format(firstWord(quickLink.name):lower())
end

local function expandQuickLink(quickLink, argument)
  local encodedArgument = encodeUrlComponent(argument)
  local expanded = quickLink.link

  for _, placeholder in ipairs({ "argument", "query", "id" }) do
    expanded = expanded:gsub("{" .. placeholder .. "}", function()
      return encodedArgument
    end)
  end

  return expanded
end

local function openQuickLink(quickLink, argument)
  argument = trim(argument)

  if argument == "" and quickLinkRequiresArgument(quickLink) then
    hs.alert.show(("Type %s then press Enter"):format(quickLinkInputHint(quickLink)))
    return
  end

  local url = expandQuickLink(quickLink, argument)
  local ok = hs.urlevent.openURL(url)

  if not ok then
    hs.alert.show("Could not open quick link")
    print(("-- raycast-lite: could not open URL: %s"):format(url))
  end
end

local function normalizeShortcutList(shortcuts)
  local normalized = {}

  if type(shortcuts) ~= "table" then
    return normalized
  end

  for _, shortcut in ipairs(shortcuts) do
    local name = nil
    local acceptsInput = nil
    local actionCount = nil

    if type(shortcut) == "table" then
      name = shortcut.name
      acceptsInput = shortcut.acceptsInput
      actionCount = shortcut.actionCount
    elseif type(shortcut) == "string" then
      name = shortcut
    end

    if type(name) == "string" and name ~= "" then
      table.insert(normalized, {
        name = name,
        acceptsInput = acceptsInput,
        actionCount = actionCount,
      })
    end
  end

  table.sort(normalized, function(left, right)
    return left.name:lower() < right.name:lower()
  end)

  return normalized
end

local function listShortcutsWithHammerspoon()
  if not hs.shortcuts or type(hs.shortcuts.list) ~= "function" then
    return nil, "hs.shortcuts.list is unavailable"
  end

  local ok, shortcuts = pcall(hs.shortcuts.list)

  if not ok then
    return nil, tostring(shortcuts)
  end

  return normalizeShortcutList(shortcuts)
end

local function listShortcutsWithCli()
  if not hs.fs.attributes("/usr/bin/shortcuts") then
    return nil, "/usr/bin/shortcuts is unavailable"
  end

  local output, ok = hs.execute("/usr/bin/shortcuts list", false)

  if not ok then
    return nil, "shortcuts list failed"
  end

  local shortcuts = {}

  for line in tostring(output or ""):gmatch("[^\r\n]+") do
    line = trim(line)

    if line ~= "" then
      table.insert(shortcuts, line)
    end
  end

  return normalizeShortcutList(shortcuts)
end

local function loadShortcuts()
  local now = hs.timer.secondsSinceEpoch()

  if shortcutsCache and now - shortcutsCacheTime < shortcutsCacheTtl then
    return shortcutsCache
  end

  local shortcuts, hammerspoonError = listShortcutsWithHammerspoon()

  if not shortcuts then
    local cliError = nil
    shortcuts, cliError = listShortcutsWithCli()

    if not shortcuts then
      shortcuts = {}

      if not shortcutListErrorShown then
        shortcutListErrorShown = true
        hs.alert.show("Could not list Shortcuts")
        print(("-- raycast-lite: could not list shortcuts: %s; %s"):format(hammerspoonError, cliError))
      end
    end
  end

  shortcutsCache = shortcuts
  shortcutsCacheTime = now
  return shortcutsCache
end

local function shortcutSubText(shortcut)
  local details = { "Shortcut" }

  if shortcut.actionCount then
    details[#details + 1] = ("%s actions"):format(shortcut.actionCount)
  end

  if shortcut.acceptsInput then
    details[#details + 1] = "accepts input"
  end

  return table.concat(details, " · ")
end

local function quickLinkChoice(quickLink, argument)
  local hasArgument = argument and argument ~= ""
  local text = quickLink.name
  local subText = "Quick Link"

  if quickLinkRequiresArgument(quickLink) then
    subText = ("Quick Link · type %s"):format(quickLinkInputHint(quickLink))
  end

  if hasArgument then
    text = ("%s: %s"):format(quickLink.name, argument)
    subText = expandQuickLink(quickLink, argument)
  end

  return {
    text = text,
    subText = subText,
    kind = "quick_link",
    quickLink = quickLink,
    argument = hasArgument and argument or nil,
  }
end

local function shortcutChoice(shortcut)
  return {
    text = shortcut.name,
    subText = shortcutSubText(shortcut),
    kind = "shortcut",
    shortcutName = shortcut.name,
  }
end

local function stripLeadingWhitespace(value)
  return tostring(value or ""):gsub("^%s+", "")
end

local function splitCommandInput(query)
  local input = stripLeadingWhitespace(query)
  local command, argument = input:match("^(%S+)%s(.*)$")

  if command then
    return command, argument or "", true
  end

  return trim(input), nil, false
end

local function quickLinkFullNameArgument(quickLink, query)
  local input = stripLeadingWhitespace(query)
  local inputLower = input:lower()
  local quickLinkName = quickLink.name
  local quickLinkNameLower = quickLinkName:lower()
  local quickLinkPrefix = quickLinkNameLower .. " "

  if inputLower == quickLinkNameLower then
    return nil, true
  end

  if inputLower:sub(1, #quickLinkPrefix) == quickLinkPrefix then
    return trim(input:sub(#quickLinkName + 2)), true
  end

  return nil, false
end

local function quickLinkNameContainsCommand(quickLink, command)
  command = trim(command):lower()

  if command == "" then
    return false
  end

  for word in quickLink.name:gmatch("%S+") do
    if word:lower():sub(1, #command) == command then
      return true
    end
  end

  return false
end

local function quickLinkArgumentForQuery(quickLink, query)
  local trimmedQuery = trim(query)

  if trimmedQuery == "" then
    return nil, 1, false
  end

  local fullNameArgument, fullNameMatched = quickLinkFullNameArgument(quickLink, query)

  if fullNameMatched then
    return fullNameArgument ~= "" and fullNameArgument or nil, 1, true
  end

  local command, argument, hasArgumentSeparator = splitCommandInput(query)

  if quickLinkNameContainsCommand(quickLink, command) then
    if hasArgumentSeparator then
      argument = trim(argument)
      return argument ~= "" and argument or nil, 2, true
    end

    return nil, 2, true
  end

  if matchesQuery(quickLink.name, trimmedQuery) then
    return nil, 3, true
  end

  return trimmedQuery, 4, false
end

local function quickLinkChoices(query)
  local buckets = { {}, {}, {}, {} }
  local choices = {}
  local hasQuickLinkMatch = false

  for _, quickLink in ipairs(currentQuickLinks) do
    local argument, priority, quickLinkMatched = quickLinkArgumentForQuery(quickLink, query)
    local bucket = buckets[priority] or buckets[4]

    if quickLinkMatched then
      hasQuickLinkMatch = true
    end

    table.insert(bucket, quickLinkChoice(quickLink, argument))
  end

  for _, bucket in ipairs(buckets) do
    for _, choice in ipairs(bucket) do
      choices[#choices + 1] = choice
    end
  end

  return choices, hasQuickLinkMatch
end

local function shortcutChoices(query)
  local choices = {}

  for _, shortcut in ipairs(loadShortcuts()) do
    if matchesQuery(shortcut.name, query) then
      table.insert(choices, shortcutChoice(shortcut))
    end
  end

  return choices
end

local function appendChoices(target, source)
  for _, choice in ipairs(source) do
    target[#target + 1] = choice
  end
end

local function buildChoices(query)
  query = trim(query)

  local choices = {}
  local shortcuts = shortcutChoices(query)
  local quickLinks, hasQuickLinkMatch = quickLinkChoices(query)

  if query == "" then
    appendChoices(choices, quickLinks)
    appendChoices(choices, shortcuts)
  elseif hasQuickLinkMatch then
    appendChoices(choices, quickLinks)
    appendChoices(choices, shortcuts)
  elseif #shortcuts > 0 then
    appendChoices(choices, shortcuts)
    appendChoices(choices, quickLinks)
  else
    appendChoices(choices, quickLinks)
  end

  return choices
end

local function updateChoices(query)
  if chooser then
    chooser:choices(buildChoices(query))
  end
end

local function forgetTask(task)
  runningTasks[task] = nil
end

local function runShortcutWithCli(shortcutName)
  local task = nil

  task = hs.task.new("/usr/bin/shortcuts", function(exitCode, stdout, stderr)
    forgetTask(task)

    if exitCode ~= 0 then
      hs.alert.show(("Shortcut failed: %s"):format(shortcutName))
      print(("-- raycast-lite: shortcut failed: %s\n%s%s"):format(shortcutName, stdout or "", stderr or ""))
    end
  end, nil, { "run", shortcutName })

  if not task then
    hs.alert.show("Could not run shortcut")
    print("-- raycast-lite: could not create shortcuts task")
    return
  end

  runningTasks[task] = true
  task:start()
end

local function runShortcut(shortcutName)
  if hs.shortcuts and type(hs.shortcuts.run) == "function" then
    local ok, errorMessage = pcall(hs.shortcuts.run, shortcutName)

    if ok then
      return
    end

    print(("-- raycast-lite: hs.shortcuts.run failed for %s: %s"):format(shortcutName, errorMessage))
  end

  runShortcutWithCli(shortcutName)
end

local function runAfterChooserHides(callback)
  if chooser then
    chooser:hide()
  end

  hs.timer.doAfter(0.05, callback)
end

local function activateChoice(choice)
  if not choice then
    return
  end

  if choice.kind == "shortcut" then
    local shortcutName = choice.shortcutName

    runAfterChooserHides(function()
      runShortcut(shortcutName)
    end)
    return
  end

  if choice.kind == "quick_link" then
    local quickLink = choice.quickLink
    local argument = choice.argument

    runAfterChooserHides(function()
      openQuickLink(quickLink, argument)
    end)
  end
end

local function buildChooser()
  local commandChooser = hs.chooser.new(activateChoice)

  commandChooser:placeholderText("Search Shortcuts or quick links")
  commandChooser:searchSubText(true)
  commandChooser:queryChangedCallback(function(query)
    updateChoices(query or commandChooser:query())
  end)
  return commandChooser
end

local function showChooser()
  if not chooser then
    chooser = buildChooser()
  end

  chooser:query(nil)
  updateChoices("")
  chooser:show()
end

function M.start()
  local config, configError = loadConfig()

  if not config then
    notifyConfigProblem("raycast-lite disabled: create raycast.config.lua", configError)
    return false
  end

  local quickLinks, quickLinksError = normalizeQuickLinks(config)

  if not quickLinks then
    notifyConfigProblem("raycast-lite disabled: fix raycast.config.lua", quickLinksError)
    return false
  end

  currentQuickLinks = quickLinks
  chooser = buildChooser()
  launcherHotkey = hs.hotkey.bind({ "alt" }, "space", showChooser)
  return launcherHotkey ~= nil
end

return M
