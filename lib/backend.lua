local input_channel = love.thread.getChannel("skyscraper-command")
local output_channel = love.thread.getChannel("skyscraper-output")

while true do
  local command = input_channel:demand()
  local parser = require("lib.parser")
  local output = io.popen(command)
  -- local output = io.popen("sh lib/script.sh")
  if not output then
    output_channel:push("error")
  end

  if output then
    for line in output:lines() do
      local game = parser.parse(line)
      if game then
        output_channel:push(game)
      end
    end
    output:close()
  end
end
