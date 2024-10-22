local input_channel = love.thread.getChannel("skyscraper-command")
local output_channel = love.thread.getChannel("skyscraper-output")

while true do
  local command = input_channel:demand()
  local parser = require("lib.parser")
  local output = io.popen(command)
  if not output then
    output_channel:push({ data = {}, error = "Failed to run Skyscraper" })
  end

  if output then
    for line in output:lines() do
      -- print(line)
      local data, error = parser.parse(line)
      if next(data) ~= nil or error ~= "" then
        output_channel:push({ data = data, error = error })
      end
      if error ~= "" then
        break
      end
    end
    output:close()
  end
end
