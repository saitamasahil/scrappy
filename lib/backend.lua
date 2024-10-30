require("globals")
local parser = require("lib.parser")

while true do
  -- Demand a table with command, platform, type, and game from INPUT_CHANNEL
  local input_data = INPUT_CHANNEL:demand()

  -- Extract the command, platform, type, and game
  local command = input_data.command
  local current_platform = input_data.platform
  local operation_type = input_data.op
  local game = input_data.game:gsub("%.%w+$", "") -- Remove file extension from game

  OUTPUT_CHANNEL:push({ data = {}, error = nil, loading = true })

  local stderr_to_stdout = " 2>&1"
  local output = io.popen(command .. stderr_to_stdout)

  print(string.format("Running command: %s\nPlatform: %s | Game: %s\n", command, current_platform, game))

  if output then
    for line in output:lines() do
      -- print(line)
      local data, error = parser.parse(line)
      if next(data) ~= nil then
        -- data.platform = current_platform
        OUTPUT_CHANNEL:push({
          data = {
            title = game,
            platform = current_platform,
            status = operation_type == "fetch" and "fetching" or "generating",
          },
          error = error,
          loading = false
        })
      end
      if error ~= nil and error ~= "" then
        print("ERROR: " .. error)
        break
      end
    end
    output:close()
    -- OUTPUT_CHANNEL:push({ loading = false })
  else
    OUTPUT_CHANNEL:push({ data = {}, error = "Failed to run Skyscraper", loading = false })
  end
end

function love.threaderror(thread, errorstr)
  print(errorstr)
  OUTPUT_CHANNEL:push({ data = {}, error = errorstr, loading = false })
end
