local M = {}
local listeners = {}
local failed = false
local serverPath = '/Applications/UURemote.app/Contents/Helpers/UURemoteServer'
local muxPath = '/Applications/UURemote.app/Contents/Helpers/tmux/uuyc-mux'

local function probeFailed(message)
  if not failed then
    print('-- uuremote-probe: probe failed: ' .. message)
  end
  failed = true
  for _, listener in ipairs(listeners) do
    local ok, err = pcall(listener, nil, message)
    if not ok then print('-- uuremote-probe: listener failed: ' .. tostring(err)) end
  end
  M.busy = false
end

local function task(path, args, callback)
  M.task = hs.task.new(path, function(code, stdout, stderr)
    M.task = nil
    callback(code, stdout, stderr)
  end, args)
  if not M.task or not M.task:start() then
    probeFailed('Could not start ' .. path)
  end
end

local function accept(sample)
  if failed then print('-- uuremote-probe: probe recovered') end
  failed = false
  for _, listener in ipairs(listeners) do
    local ok, err = pcall(listener, sample)
    if not ok then print('-- uuremote-probe: listener failed: ' .. tostring(err)) end
  end
  M.busy = false
end

local function poll()
  if M.busy then
    if os.time() - M.startedAt > 10 then
      if M.task then M.task:terminate() end
    end
    return
  end
  M.busy = true
  M.startedAt = os.time()
  task('/bin/bash', { '-o', 'pipefail', '-c', [[LC_ALL=C /bin/ps -axo pid=,ppid=,lstart=,comm= | /usr/bin/awk '/\/Applications\/UURemote.app\/Contents\/Helpers\/(UURemoteServer|tmux\/uuyc-mux)$/']] }, function(code, stdout, stderr)
    if code ~= 0 then return probeFailed('process probe exit ' .. code .. ': ' .. stderr) end
    local processes, servers = {}, {}
    for line in stdout:gmatch('[^\n]+') do
      local pid, parent, started, executable = line:match('^%s*(%d+)%s+(%d+)%s+(%a+%s+%a+%s+%d+%s+[%d:]+%s+%d+)%s+(.+)$')
      if pid then
        processes[pid] = { pid = tonumber(pid), parent_pid = tonumber(parent), started = started, executable = executable }
        if executable == serverPath then servers[pid] = true end
      end
    end
    if not next(processes) and stdout:match('%S') then return probeFailed('Unrecognized ps output') end
    local sample = { connections = {}, attachments = {}, sessions = {}, peerCount = 0 }
    for pid, process in pairs(processes) do
      if process.executable == muxPath then
        local group = servers[tostring(process.parent_pid)] and sample.attachments or sample.sessions
        group[pid .. ':' .. process.started] = process
      end
    end
    local pids = {}
    for pid in pairs(servers) do table.insert(pids, pid) end
    if #pids == 0 then return accept(sample) end
    task('/usr/sbin/lsof', { '-nP', '-a', '-p', table.concat(pids, ','), '-iTCP', '-sTCP:ESTABLISHED', '-Fpn' }, function(status, output, errors)
      if (status ~= 0 and status ~= 1) or errors:match('%S') or (status == 1 and output:match('%S')) then
        return probeFailed('lsof exit ' .. status .. ': ' .. errors)
      end
      local pid
      for line in output:gmatch('[^\n]+') do
        if line:sub(1, 1) == 'p' then pid = line:sub(2) end
        if line:sub(1, 1) == 'n' then
          local endpoint = line:sub(2)
          local remote = endpoint:match('%->(.+)$')
          if not remote or not pid then return probeFailed('Unrecognized lsof endpoint') end
          local address, port = remote:match('^%[([^%]]+)%]:(%d+)$')
          if not address then address, port = remote:match('^(.-):(%d+)$') end
          if not address then return probeFailed('Unrecognized remote address') end
          sample.connections[pid .. ':' .. endpoint] = {
            pid = tonumber(pid), endpoint = endpoint, remote_ip = address, remote_port = tonumber(port),
            interpretation = port == '443' and 'unclassified_https_connection' or 'possible_remote_peer',
          }
          if port ~= '443' then sample.peerCount = sample.peerCount + 1 end
        end
      end
      accept(sample)
    end)
  end)
end

function M.subscribe(listener)
  table.insert(listeners, listener)
end

function M.start()
  if M.timer then return end
  M.timer = hs.timer.doEvery(2, poll)
  poll()
end

return M
