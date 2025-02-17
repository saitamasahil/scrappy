require("globals")

local parser = {}
local line_patterns = {
  "found!",
  "Skipping game",
  "not found",
  "No entries to scrape..."
}
local game_title_patterns = {
  FOUND = "Game '(.-)' found!",
  NOT_FOUND = "Game '(.-)' not found",
  SKIPPED = "Skipping game '(.-)' since"
}
local log_patterns = {
  "Running Skyscraper v",
  "Fetching limits for user",
  "Starting scraping run",
  "Resource gathering run"
}

--[[
  Parse a line of Skyscraper output, returning:
  - A line to be logged, or a game title if found
  - An error message if the line is an error
  - A boolean indicating whether the line is a log line
--]]
function parser.parse(line)
  local game_pattern = "'([^']*'.-)'"
  local line_match = nil

  -- for _, pattern in ipairs(log_patterns) do
  --   if line:find(pattern) then
  --     return line, nil, true
  --   end
  -- end

  for _, pattern in ipairs(line_patterns) do
    if line:find(pattern) then
      line_match = pattern
      break
    end
  end

  if line_match then
    -- print("Line matched: " .. line)
    -- Extract game title
    if line_match == line_patterns[1] then -- Found
      local game_title = string.match(line, game_title_patterns.FOUND)
      return game_title, nil, false
    elseif line_match == line_patterns[2] then -- Skipped
      local game_title = string.match(line, game_title_patterns.SKIPPED)
      return game_title, nil, false
    elseif line_match == line_patterns[3] then -- Not found
      local game_title = string.match(line, game_title_patterns.NOT_FOUND)
      return game_title, nil, true
    end
    return "N/A", nil, true
  else
    -- print("Line did not match: " .. line)
    for _, error in ipairs(SKYSCRAPER_ERRORS) do
      if line:find(error) then
        return nil, line, true
      end
    end
    return nil, nil, nil
  end
end

return parser
