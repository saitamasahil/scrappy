local log = {}

local socket = require("socket")
local log_backend = love.thread.newThread("lib/log_backend.lua")
local log_channel = love.thread.getChannel("log")

local start_time

function log.start()
  start_time = socket.gettime()
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
