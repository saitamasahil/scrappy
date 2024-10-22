require("consts")
local parser = require("lib.parser")

while true do
  local command = INPUT_CHANNEL:demand()
  OUTPUT_CHANNEL:push({ data = {}, error = "", loading = true })
  local output = io.popen(command)
  if not output then
    OUTPUT_CHANNEL:push({ data = {}, error = "Failed to run Skyscraper", loading = false })
  end

  if output then
    for line in output:lines() do
      -- print(line)
      local data, error = parser.parse(line)
      if next(data) ~= nil or error ~= "" then
        OUTPUT_CHANNEL:push({ data = data, error = error, loading = false })
      end
      if error ~= "" then
        break
      end
    end
    output:close()
  end
end
