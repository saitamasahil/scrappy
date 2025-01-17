local log = {}

local nativefs = require("lib.nativefs")
local socket = require("socket")

local log_backend = love.thread.newThread("lib/backend/log_backend.lua")
local log_channel = love.thread.getChannel("log")
local max_logs = 10

local start_time

local function cleanup_logs()
  local files = nativefs.getDirectoryItems("logs")
  if #files > max_logs then
    for i = 1, #files - max_logs do
      if files[i]:sub(-4) == ".log" then
        nativefs.remove("logs/" .. files[i])
      end
    end
  end
end

function log.start()
  start_time = socket.gettime()
  cleanup_logs()
  log_backend:start(start_time)
  log_channel:push("start")
end

function log.close()
  log_channel:push("close")
  log_backend:wait()
  log_backend:release()
end

function log.write(msg, ...)
  local origin = select(1, ...) or "scrappy"
  local now = socket.gettime()

  local time_date = os.date("%H:%M:%S:", now)
  local msg = string.format("[%s%03d] (%s) %s", time_date, (now * 1000) % 1000, origin, msg)

  log_channel:push(msg)
  return msg
end

return log
