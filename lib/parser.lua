require("globals")

local parser = {}

function parser.parse(line)
  local _, _, game_title = line:match("#(%d+)/(%d+).+Game%s+'(.-)'")

  local success = true
  if line:find("not found") then
    success = false
  end

  if game_title then
    return {
      title = game_title,
      success = success
    }, nil
  else
    -- print("Line did not match: " .. line)
    for _, error in ipairs(SKYSCRAPER_ERRORS) do
      if line:find(error) then
        return {}, line
      end
    end
    return {}, nil
  end
end

return parser
