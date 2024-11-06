require("globals")
local parser = require("lib.parser")
local log = require("lib.log")
local utils = require("helpers.utils")

local function log_version(output)
  if not output then
    log.write("Failed to run Skyscraper")
    return
  end

  for line in output:lines() do
    -- Attempt to parse errors
    local _, err = parser.parse(line)
    if err then
      log.write("Failed to start Skyscraper: " .. err, "skyscraper")
      break
    end

    -- Check for version pattern in the line
    local version = line:match("(%d+%.%d+%.%d+)")
    if version then
      log.write(string.format("Skyscraper version: %s\n", version))
      break
    end
  end

  output:close()
end

while true do
  ::continue::
  -- Demand a table with command, platform, type, and game from INPUT_CHANNEL
  local input_data = INPUT_CHANNEL:demand()

  -- Extract the command, platform, type, and game
  local command = input_data.command
  local current_platform = input_data.platform
  local operation_type = input_data.op
  local game = utils.get_filename(input_data.game)
  local task_id = input_data.task_id

  local stderr_to_stdout = " 2>&1"
  local output = io.popen(command .. stderr_to_stdout)

  if input_data.version then -- Special command. Log version only
    log_version(output)
    goto continue
  end

  OUTPUT_CHANNEL:push({ data = {}, error = nil, loading = true })

  log.write(string.format("Running command: %s", command))
  log.write(string.format("Platform: %s | Game: %s\n", current_platform, game))

  if not output then
    log.write("Failed to run Skyscraper")
    OUTPUT_CHANNEL:push({ data = {}, error = "Failed to run Skyscraper", loading = false })
    goto continue
  end

  for line in output:lines() do
    line = utils.strip_ansi_colors(line)
    if game ~= "fake-rom" then log.write(line, "skyscraper") end
    local data, error = parser.parse(line)
    if next(data) ~= nil and operation_type == "generate" then
      OUTPUT_CHANNEL:push({
        data = {
          title = game,
          platform = current_platform,
        },
        task_id = task_id,
        success = data.success,
        error = error,
        loading = false
      })
    end

    if error ~= nil and error ~= "" then
      log.write("ERROR: " .. error, "skyscraper")
      OUTPUT_CHANNEL:push({ data = {}, error = error, loading = false })
      break
    end
  end

  output:close()
  OUTPUT_CHANNEL:push({ loading = false })
end

function love.threaderror(thread, errorstr)
  print(errorstr)
  OUTPUT_CHANNEL:push({ data = {}, error = errorstr, loading = false })
  log.write(errorstr)
end
