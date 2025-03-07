local utils = require("helpers.utils")

local metadata_parser = {}

-- Parses the Pegasus frontend metadata file
function metadata_parser.parse(content)
  local games = {}
  local current_game = {}

  for line in content:gmatch("[^\r\n]+") do
    -- Trim leading and trailing whitespace
    line = line:match("^%s*(.-)%s*$")

    -- Check if the line starts a new game block
    if line:match("^game:") then
      -- If there's a current game, add it to the games table
      if next(current_game) ~= nil then
        table.insert(games, current_game)
      end
      -- Start a new game block
      current_game = {}
      current_game.title = line:match("^game:%s*(.+)")
    elseif line:match("^file:") then
      -- Extract the full path
      local full_path = line:match("^file:%s*(.+)")
      -- Extract the filename from the full path
      current_game.filename = utils.get_filename(full_path:match("([^/]+)$"))
    elseif line:match("^description:") then
      current_game.description = line:match("^description:%s*(.+)")
    elseif line:match("^publisher:") then
      current_game.publisher = line:match("^publisher:%s*(.+)")
    elseif line:match("^genre:") then
      current_game.genre = line:match("^genre:%s*(.+)")
    end
  end

  -- Add the last game to the games table
  if next(current_game) ~= nil then
    table.insert(games, current_game)
  end

  return games
end

return metadata_parser
