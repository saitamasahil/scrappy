local log     = require("lib.log")
local config  = require("helpers.config")
local utils   = require("helpers.utils")
local muos    = require("helpers.muos")

local artwork = {}


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
  local path = string.format("%s/%s/media/covers/%s.png", utils.strip_quotes(output_path), platform, game)
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

  destination_folder = string.format("%s/%s/box", catalogue_path, destination_folder)
  local _, err = nativefs.write(string.format("%s/%s.png", destination_folder, game), scraped_art)
  if err then
    log.write(err)
  end
end

return artwork
