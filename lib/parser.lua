require("consts")

local parser = {}

local games = {
  total = 0,
  current = 0,
  titles = {}
}

function parser.parse(line)
  local game_number, total_games, game_title = line:match("#(%d+)/(%d+).+Game%s+'(.-)'")

  if game_number and total_games and game_title then
    -- print("Line matched: " .. line)
    games.current = tonumber(game_number)
    games.total = tonumber(total_games)

    table.insert(games.titles, game_title)

    return {
      index = tonumber(game_number),
      total = tonumber(total_games),
      title = game_title
    }, ""
  else
    -- print("Line did not match: " .. line)
    for _, error in ipairs(SKYSCRAPER_ERRORS) do
      if line:match(error) then
        return {}, error
      end
    end
    return {}, ""
  end
end

function parser.string_to_table(game_string)
  local game_number, total_games, game_title = game_string:match("(%d+)/(%d+)%s+%-%s+(.*)")

  if game_number and total_games and game_title then
    return {
      index = tonumber(game_number),
      total = tonumber(total_games),
      title = game_title
    }
  else
    return nil
  end
end

function parser.get_games()
  return games
end

function parser.print_games()
  print(string.format("Total Games: %d, Current Game: %d", games.total, games.current))
  print("Titles:")
  for i, title in ipairs(games.titles) do
    print("  " .. title)
  end
end

return parser
