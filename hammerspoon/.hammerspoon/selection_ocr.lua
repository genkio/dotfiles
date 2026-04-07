local M = {}

local hotkey = nil
local launchTimer = nil
local captureTask = nil
local ocrTask = nil
local captureLaunchDelaySeconds = 0.15

local function parentDirectory(path)
  return path:match("^(.*)/[^/]+$")
end

local function trim(text)
  if type(text) ~= "string" then
    return ""
  end

  return text:match("^%s*(.-)%s*$")
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

local function joinPath(directory, name)
  if directory:sub(-1) == "/" then
    return directory .. name
  end

  return directory .. "/" .. name
end

local function helperScriptCandidates()
  local candidates = {}
  local source = debug.getinfo(1, "S").source

  if type(source) == "string" and source:sub(1, 1) == "@" then
    local modulePath = source:sub(2)
    local resolvedPath = hs.fs.pathToAbsolute(modulePath)

    uniqueAppend(candidates, joinPath(parentDirectory(modulePath), "selection_ocr.swift"))

    if resolvedPath and resolvedPath ~= modulePath then
      uniqueAppend(candidates, joinPath(parentDirectory(resolvedPath), "selection_ocr.swift"))
    end
  end

  uniqueAppend(candidates, joinPath(hs.configdir, "selection_ocr.swift"))
  return candidates
end

local function helperScriptPath()
  for _, path in ipairs(helperScriptCandidates()) do
    if hs.fs.attributes(path) then
      return path
    end
  end

  return helperScriptCandidates()[1]
end

local function cleanup(path)
  if path and hs.fs.attributes(path) then
    os.remove(path)
  end
end

local function stopTimer(timer)
  if timer then
    timer:stop()
  end

  return nil
end

local function temporaryCapturePath()
  local tempDirectory = os.getenv("TMPDIR") or "/tmp"
  local filename = ("selection-ocr-%d.png"):format(hs.timer.absoluteTime())
  return joinPath(tempDirectory, filename)
end

local function taskErrorOutput(stdOut, stdErr)
  local output = trim(stdErr)

  if output ~= "" then
    return output
  end

  return trim(stdOut)
end

local function finishOCR(output)
  local text = trim(output)

  if text == "" then
    hs.alert.show("No text recognized")
    return
  end

  hs.pasteboard.setContents(text)
  hs.alert.show("OCR text copied")
end

local function runOCR(scriptPath, capturePath)
  ocrTask = hs.task.new("/usr/bin/swift", function(exitCode, stdOut, stdErr)
    ocrTask = nil
    cleanup(capturePath)

    if exitCode ~= 0 then
      hs.alert.show("OCR failed")
      print("-- selection_ocr: " .. taskErrorOutput(stdOut, stdErr))
      return
    end

    finishOCR(stdOut)
  end, { scriptPath, capturePath })

  if not ocrTask then
    cleanup(capturePath)
    hs.alert.show("OCR failed")
    print("-- selection_ocr: could not create OCR task")
    return
  end

  if not ocrTask:start() then
    ocrTask = nil
    cleanup(capturePath)
    hs.alert.show("OCR failed")
    print("-- selection_ocr: could not start OCR task")
  end
end

local function startSelectionOCR()
  local scriptPath = helperScriptPath()

  if not hs.fs.attributes(scriptPath) then
    hs.alert.show("OCR helper missing")
    print("-- selection_ocr: missing helper script at " .. scriptPath)
    return
  end

  if captureTask and captureTask:isRunning() then
    return
  end

  if ocrTask and ocrTask:isRunning() then
    return
  end

  local capturePath = temporaryCapturePath()
  captureTask = hs.task.new("/usr/sbin/screencapture", function(exitCode, stdOut, stdErr)
    captureTask = nil

    if exitCode ~= 0 or not hs.fs.attributes(capturePath) then
      local errorOutput = taskErrorOutput(stdOut, stdErr)

      if errorOutput ~= "" then
        print("-- selection_ocr: " .. errorOutput)
      end

      cleanup(capturePath)
      return
    end

    runOCR(scriptPath, capturePath)
  end, { "-i", "-x", capturePath })

  if not captureTask then
    hs.alert.show("Screen capture failed")
    print("-- selection_ocr: could not create capture task")
    cleanup(capturePath)
    return
  end

  if not captureTask:start() then
    captureTask = nil
    hs.alert.show("Screen capture failed")
    print("-- selection_ocr: could not start capture task")
    cleanup(capturePath)
  end
end

local function scheduleSelectionOCR()
  launchTimer = stopTimer(launchTimer)
  launchTimer = hs.timer.doAfter(captureLaunchDelaySeconds, function()
    launchTimer = nil
    startSelectionOCR()
  end)
end

function M.start()
  if hotkey then
    hotkey:delete()
  end

  launchTimer = stopTimer(launchTimer)
  hotkey = hs.hotkey.bind({ "cmd", "shift" }, "s", function() end, scheduleSelectionOCR)
  return true
end

return M
