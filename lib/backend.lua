require("globals")
local parser = require("lib.parser")
local log = require("lib.log")
local utils = require("helpers.utils")

while true do
  -- Demand a table with command, platform, type, and game from INPUT_CHANNEL
  local input_data = INPUT_CHANNEL:demand()

  -- Extract the command, platform, type, and game
  local command = input_data.command
  local current_platform = input_data.platform
  local operation_type = input_data.op
  local game = utils.get_filename(input_data.game)
  local task_id = input_data.task_id

  OUTPUT_CHANNEL:push({ data = {}, error = nil, loading = true })

  local stderr_to_stdout = " 2>&1"
  local output = io.popen(command .. stderr_to_stdout)

  log.write(string.format("Running command: %s", command))
  log.write(string.format("Platform: %s | Game: %s\n", current_platform, game))

  if output then
    if game ~= "fake-rom" then
      for line in output:lines() do
        line = utils.strip_ansi_colors(line)
        log.write(line, "skyscraper")
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
    end
    output:close()
    OUTPUT_CHANNEL:push({ loading = false })
  else
    OUTPUT_CHANNEL:push({ data = {}, error = "Failed to run Skyscraper", loading = false })
    log.write("Failed to run Skyscraper")
  end
end

function love.threaderror(thread, errorstr)
  print(errorstr)
  OUTPUT_CHANNEL:push({ data = {}, error = errorstr, loading = false })
  log.write(errorstr)
end
