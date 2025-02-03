local nativefs = require("lib.nativefs")
-- local pprint   = require("lib.pprint")
local channels = require("lib.backend.channels")


local path, interval = ...
local last_modtime   = nil
local running        = true

local function get_file_modtime()
  local info = nativefs.getInfo(path, "file")
  return info and info.modtime or nil
end

local function check_file_changes()
  local curr_modtime = get_file_modtime()
  if curr_modtime ~= last_modtime then
    last_modtime = curr_modtime
    return curr_modtime
  end
  return nil
end

while running do
  -- Check for commands from the main thread
  local command = channels.WATCHER_INPUT:pop()
  if command == "stop" then
    running = false
    break
  end

  local start = os.clock()
  while os.clock() - start < interval do
    command = channels.WATCHER_INPUT:pop()
    if command == "stop" then
      running = false
      break
    end
  end

  -- Check file changes
  if running then
    local modtime = check_file_changes()
    if modtime then
      channels.WATCHER_OUTPUT:push(modtime)
    end
  end
end
