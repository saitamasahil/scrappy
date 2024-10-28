require("globals")
local parser = require("lib.parser")

while true do
  local command = INPUT_CHANNEL:demand()
  OUTPUT_CHANNEL:push({ data = {}, error = "", loading = true })
  local stderr_to_stdout = " 2>&1"
  local output = io.popen(command .. stderr_to_stdout)
  print("Command: " .. command)

  if output then
    for line in output:lines() do
      print(line)
      local data, error = parser.parse(line)
      if next(data) ~= nil or error ~= "" then
        OUTPUT_CHANNEL:push({ data = data, error = error, loading = false })
      end
      if error ~= "" then
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
