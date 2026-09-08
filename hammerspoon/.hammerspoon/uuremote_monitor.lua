local M = {}
local probe = require("uuremote_probe")
local peerNames = {}
local session
local emptyPolls = 0
local sourcePath = assert(hs.fs.pathToAbsolute(debug.getinfo(1, 'S').source:sub(2)))
local logDirectory = assert(sourcePath:match('^(.*)/[^/]+$')) .. '/logs/uuremote'
local logPath = logDirectory .. '/events.log'

local function quote(value)
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function localTimestamp()
  return (os.date('%Y-%m-%dT%H:%M:%S%z'):gsub('([+-]%d%d)(%d%d)$', '%1:%2'))
end

local function logValue(value)
  return '"' .. tostring(value):gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t') .. '"'
end

local function emit(event, data)
  local ok, err = pcall(function()
    local peers = {}
    for _, peer in ipairs(data.peers) do
      table.insert(peers, peer.device and (peer.device .. '@' .. peer.ip) or peer.ip)
    end
    local fields = {
      'time=' .. (event == 'connect' and session.connected_at or localTimestamp()),
      'level=info', 'msg=' .. event, 'peers=' .. logValue(table.concat(peers, ', ')),
    }
    if data.terminal then table.insert(fields, 'terminal=true') end
    if data.monitoring_gap then table.insert(fields, 'monitoring_gap=true') end
    if data.duration_seconds then table.insert(fields, 'duration_seconds=' .. data.duration_seconds) end
    if data.connected_at then table.insert(fields, 'connected_at=' .. data.connected_at) end
    local encoded = table.concat(fields, ' ') .. '\n'
    if (hs.fs.attributes(logPath, 'size') or 0) >= 5 * 1024 * 1024 then
      if hs.fs.attributes(logPath .. '.5') then assert(os.remove(logPath .. '.5')) end
      for index = 4, 0, -1 do
        local source = logPath .. (index == 0 and '' or '.' .. index)
        if hs.fs.attributes(source) then assert(os.rename(source, logPath .. '.' .. (index + 1))) end
      end
    end
    local file = assert(io.open(logPath, 'a'))
    local written, writeError = file:write(encoded)
    local closed, closeError = file:close()
    assert(written, writeError)
    assert(closed, closeError)
  end)
  if not ok then print('-- uuremote-monitor: log write failed: ' .. tostring(err)) end
  return ok
end

local function sessionDetails(event)
  local identified, unknown = {}, {}
  for _, peer in pairs(session.peers) do
    if peer.device_id then
      local current = identified[peer.device_id]
      local ipv4 = not peer.ip:find(':', 1, true)
      local currentIPv4 = current and not current.ip:find(':', 1, true)
      if not current or (ipv4 and not currentIPv4) or (ipv4 == currentIPv4 and peer.ip < current.ip) then
        identified[peer.device_id] = { device = peer.device_name, ip = peer.ip }
      end
    else
      table.insert(unknown, { ip = peer.ip })
    end
  end
  local peers = {}
  for _, peer in pairs(identified) do table.insert(peers, peer) end
  if #peers == 0 then peers = unknown end
  table.sort(peers, function(a, b) return a.ip < b.ip end)
  local details = { peers = peers }
  if session.terminal_observed then details.terminal = true end
  if session.monitoring_gap then details.monitoring_gap = true end
  if event == 'disconnect' then
    details.connected_at = session.connected_at
    details.duration_seconds = os.time() - session.started
  end
  return details
end

local function accept(sample)
  if not sample then
    if session then session.monitoring_gap = true end
    emptyPolls = 0
    return
  end
  if sample.peerCount > 0 or next(sample.attachments) then
    emptyPolls = 0
    local isNew = session == nil
    if isNew then
      session = {
        connected_at = localTimestamp(), started = os.time(),
        peers = {}, terminal_observed = false, monitoring_gap = false,
      }
    end
    session.terminal_observed = session.terminal_observed or next(sample.attachments) ~= nil
    for _, connection in pairs(sample.connections) do
      if connection.remote_port ~= 443 then
        local peer = peerNames[connection.remote_ip]
        session.peers[connection.remote_ip] = {
          ip = connection.remote_ip, device_name = peer and peer.name,
          device_id = peer and peer.id,
        }
      end
    end
    if not session.logged and (session.terminal_observed or os.time() - session.started >= 4) then
      session.logged = emit('connect', sessionDetails('connect'))
    end
  elseif session then
    emptyPolls = emptyPolls + 1
    if emptyPolls >= 2 then
      if not session.logged then session.logged = emit('connect', sessionDetails('connect')) end
      if session.logged and emit('disconnect', sessionDetails('disconnect')) then
        session = nil
        emptyPolls = 0
      end
    end
  end
end

local function refreshNames()
  if M.nameTask then return end
  local cli
  for _, path in ipairs({ '/opt/homebrew/bin/tailscale', '/usr/local/bin/tailscale', '/Applications/Tailscale.app/Contents/MacOS/Tailscale' }) do
    if hs.fs.attributes(path) then cli = path; break end
  end
  if not cli then return end
  M.nameTask = hs.task.new(cli, function(code, output)
    M.nameTask = nil
    if code ~= 0 then peerNames = {}; return end
    local ok, status = pcall(hs.json.decode, output)
    if not ok or type(status) ~= 'table' then peerNames = {}; return end
    local names = {}
    for id, peer in pairs(status.Peer or {}) do
      local name = (peer.DNSName or ''):match('^([^.]+)') or peer.HostName
      if name then
        for _, address in ipairs(peer.TailscaleIPs or {}) do names[address] = { name = name, id = id } end
      end
    end
    peerNames = names
  end, { 'status', '--json' })
  if M.nameTask then M.nameTask:start() end
end

function M.start()
  if M.started then return end
  local _, ok = hs.execute('/bin/mkdir -p ' .. quote(logDirectory) .. ' && /bin/chmod 700 ' .. quote(logDirectory))
  if not ok then error('Cannot create private UURemote log directory') end
  local file = assert(io.open(logPath, 'a'))
  assert(file:close())
  refreshNames()
  M.nameTimer = hs.timer.doEvery(300, refreshNames)
  probe.subscribe(accept)
  M.started = true
  probe.start()
end

return M
