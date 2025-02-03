local channels  = require("lib.backend.channels")

local watcher   = {}
watcher.__index = watcher

function watcher.new(path, interval)
  local self = setmetatable({}, watcher)
  self.path = path
  self.interval = interval or 2
  return self
end

function watcher:init()
  print("Watching file: " .. self.path)
  local thread = love.thread.newThread("lib/backend/watcher_backend.lua")
  thread:start(self.path, self.interval)
end

function watcher:update(callback)
  local modtime = channels.WATCHER_OUTPUT:pop()
  if modtime then callback(modtime) end
end

function watcher:stop()
  channels.WATCHER_INPUT:push("stop")
end

return watcher
