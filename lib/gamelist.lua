local gamelist_parser = {}

local function extract_tag_content(s, tag)
  return string.match(s, "<" .. tag .. "%s*[^>]*>(.-)</" .. tag .. ">") or ""
end

function gamelist_parser.parse(xml)
  local games = {}
  for game_block in string.gmatch(xml, "<game>(.-)</game>") do
    local game = {
      path = extract_tag_content(game_block, "path"),
      name = extract_tag_content(game_block, "name"),
      desc = extract_tag_content(game_block, "desc")
    }
    table.insert(games, game)
  end
  return games
end

return gamelist_parser
