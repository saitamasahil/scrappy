require("globals")

local parser = {}

function parser.parse(line)
  local _, _, game_title = line:match("#(%d+)/(%d+).+Game%s+'(.-)'")
  if line:find("No entries to scrape...") then
    return { title = "", success = false }, nil
  end

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
