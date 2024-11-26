require("globals")

local parser = {}

function parser.parse(line, game)
  local patterns = { "found!", "Skipping game", "not found", "No entries to scrape..." }
  local line_match = nil

  for _, pattern in ipairs(patterns) do
    if line:find(pattern) then
      line_match = pattern
      break
    end
  end

  if line_match then
    -- print("Line matched: " .. line)
    return line_match == patterns[1] or line_match == patterns[2], nil
  else
    -- print("Line did not match: " .. line)
    for _, error in ipairs(SKYSCRAPER_ERRORS) do
      if line:find(error) then
        return false, line
      end
    end
    return nil, nil
  end
end

return parser
