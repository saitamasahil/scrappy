require("globals")
local parser = require("lib.parser")
local nativefs = require("lib.nativefs")

local log = {}
local function strip_ansi_colors(str)
  return str:gsub("\27%[%d*;*%d*m", "")
end

local function write_log()
  local timestamp = os.date("%Y%m%d%H%M")
  nativefs.write(string.format("logs/scrappy-%s.log", timestamp), table.concat(log, "\n"))
  log = {}
end

while true do
  -- Demand a table with command, platform, type, and game from INPUT_CHANNEL
  local input_data = INPUT_CHANNEL:demand()

  -- Extract the command, platform, type, and game
  local command = input_data.command
  local current_platform = input_data.platform
  local operation_type = input_data.op
  local game = input_data.game:gsub("%.%w+$", "") -- Remove file extension from game
  local task_id = input_data.task_id

  OUTPUT_CHANNEL:push({ data = {}, error = nil, loading = true })

  local stderr_to_stdout = " 2>&1"
  local output = io.popen(command .. stderr_to_stdout)

  log[#log + 1] = string.format("Running command: %s\nPlatform: %s | Game: %s\n", command, current_platform, game)
  print(log[#log])

  if output then
    for line in output:lines() do
      line = strip_ansi_colors(line)
      -- print(line)
      log[#log + 1] = line
      local data, error = parser.parse(line)
      if next(data) ~= nil then
        OUTPUT_CHANNEL:push({
          data = {
            title = game,
            platform = current_platform,
            status = operation_type == "fetch" and "fetching" or "generating",
          },
          task_id = task_id,
          error = error,
          loading = false
        })
      end
      if error ~= nil and error ~= "" then
        print("ERROR: " .. error)
        OUTPUT_CHANNEL:push({ data = {}, error = error, loading = false })
        break
      end
    end
    output:close()
    -- OUTPUT_CHANNEL:push({ loading = false })
  else
    OUTPUT_CHANNEL:push({ data = {}, error = "Failed to run Skyscraper", loading = false })
  end
  if game ~= "fake-rom" and INPUT_CHANNEL:getCount() == 0 then
    write_log()
  end
end

function love.threaderror(thread, errorstr)
  print(errorstr)
  OUTPUT_CHANNEL:push({ data = {}, error = errorstr, loading = false })
  log[#log + 1] = errorstr
  write_log()
end
