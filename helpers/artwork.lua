local log      = require("lib.log")
local gamelist = require("lib.gamelist")
local config   = require("helpers.config")
local utils    = require("helpers.utils")
local muos     = require("helpers.muos")

local artwork  = {
  cached_game_ids = {},
  output_type = "box",
}


local user_config, skyscraper_config = config.user_config, config.skyscraper_config

function artwork.get_artwork_path()
  local artwork_xml = skyscraper_config:read("main", "artworkXml")
  if not artwork_xml or artwork_xml == "\"\"" then return nil end
  artwork_xml = artwork_xml:gsub('"', '')
  return artwork_xml
end

function artwork.get_artwork_name()
  local artwork_path = artwork.get_artwork_path()
  if not artwork_path then return nil end
  local artwork_name = artwork_path:match("([^/]+)%.xml$")
  return artwork_name
end

function artwork.get_template_resolution(xml_path)
  local xml_content = nativefs.read(xml_path)
  if not xml_content then
    return nil
  end

  local width, height = xml_content:match('<output [^>]*width="(%d+)"[^>]*height="(%d+)"')

  if width and height then
    return width .. "x" .. height
  end
  return nil
end

function artwork.copy_to_catalogue(platform, game)
  log.write(string.format("Copying artwork for %s: %s", platform, game))
  local _, output_path = skyscraper_config:get_paths()
  local _, catalogue_path = user_config:get_paths()
  if output_path == nil or catalogue_path == nil then
    log.write("Missing paths from config")
    return
  end
  output_path = utils.strip_quotes(output_path)
  local path = string.format("%s/%s/media/covers/%s.png", output_path, platform, game)
  local destination_folder = muos.platforms[platform]
  if not destination_folder then
    log.write("Catalogue destination folder not found")
    return
  end

  local scraped_art = nativefs.newFileData(path)
  if not scraped_art then
    log.write("Scraped artwork not found")
    return
  end

  local output_folder = string.format("%s/%s/%s", catalogue_path, destination_folder, artwork.output_type)
  local _, err = nativefs.write(string.format("%s/%s.png", output_folder, game), scraped_art)
  if err then
    log.write(err)
  end

  local xml = nativefs.read(string.format("%s/%s/gamelist.xml", output_path, platform))
  if xml then
    local list = gamelist.parse(xml)
    if list then
      for _, entry in ipairs(list) do
        if utils.get_filename_from_path(entry.path) == utils.escape_html(game) then
          local text_folder = string.format("%s/%s/text", catalogue_path, destination_folder)
          local _, err = nativefs.write(string.format("%s/%s.txt", text_folder, game), utils.unescape_html(entry.desc))
          if err then log.write(err) end
          break
        end
      end
    end
  else
    log.write("Failed to load gamelist.xml for " .. platform)
  end
end

function artwork.process_cached_data()
  log.write("Processing cached data")
  local cached_games = {}
  local cache_folder = skyscraper_config:read("main", "cacheFolder")
  if not cache_folder then return end
  cache_folder = utils.strip_quotes(cache_folder)
  local items = nativefs.getDirectoryItems(cache_folder)
  if not items then return end

  for _, platform in ipairs(items) do
    local quickid = nativefs.read(string.format("%s/%s/quickid.xml", cache_folder, platform))
    local db = nativefs.read(string.format("%s/%s/db.xml", cache_folder, platform))
    if quickid then
      local lines = utils.split(quickid, "\n")
      for _, line in ipairs(lines) do
        if line:find("<quickid%s") then
          local filepath = line:match('filepath="([^"]+)"')
          if filepath then
            local filename = filepath:match("([^/]+)$")
            local id = line:match('id="([^"]+)"')
            artwork.cached_game_ids[filename] = id
          end
        end
      end
    end
    if db then
      local lines = utils.split(db, "\n")
      for _, line in ipairs(lines) do
        if line:find("<resource%s") then
          local id = line:match('id="([^"]+)"')
          if id then
            cached_games[id] = true
          end
        end
      end
    end

    for filename, id in pairs(artwork.cached_game_ids) do
      if not cached_games[id] then
        artwork.cached_game_ids[filename] = nil
      end
    end
  end

  log.write("Finished processing cached data")
end

return artwork
