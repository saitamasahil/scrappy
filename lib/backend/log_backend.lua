local start_time  = ...

local nativefs    = require("lib.nativefs")
local log_channel = require("lib.backend.channels").LOG_INPUT

local function log_filename()
  return string.format("logs/scrappy-%s.log", os.date("%Y-%m-%d-%H-%M", start_time))
end

while true do
  local input = log_channel:demand()

  if input == "close" then
    break
  elseif input == "start" then
    nativefs.write(log_filename(), "")
  else
    nativefs.append(log_filename(), input .. "\n")
  end
end
