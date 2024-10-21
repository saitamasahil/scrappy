local ini = require("lib.ini")
local nativefs = require("lib.nativefs")
local work_dir = nativefs.getWorkingDirectory()

local skyscraper = {
  base_command = "./Skyscraper ",
  module = "screenscraper",
  config_path = "",
}

local thread
local channel

local function push_command(command)
  channel = love.thread.getChannel("skyscraper-command")
  if channel then
    channel:push(command)
  end
end

function skyscraper.init(config_path)
  print("Initializing Skyscraper")
  skyscraper.config_path = work_dir .. "/" .. config_path

  local quick_id = nativefs.read("sample/quickid.xml")
  if quick_id then
    print("Writing quickid.xml")
    quick_id = string.gsub(quick_id, "filepath=\"%S+\"", "filepath=\"" .. work_dir .. "/sample/fake-rom.zip\"")
    nativefs.write("sample/quickid.xml", quick_id)
  end

  local ini_file = ini.load(config_path)
  if ini_file then
    print("Found config.ini, using it")
  else
    print("Config file not present, creating one")
    ini_file = ini.load("skyscraper_config.ini.example")
    ini.addKey(ini_file, "main", "inputFolder", "\"/mnt/mmc/roms\"")
    ini.addKey(ini_file, "main", "cacheFolder", '"' .. work_dir .. "/data/cache" .. '"')
    ini.addKey(ini_file, "main", "gameListFolder", '"' .. work_dir .. "/data/output" .. '"')
    ini.addKey(ini_file, "main", "artworkXml", '"' .. work_dir .. "/templates/artwork.xml" .. '"')
    if ini.save(ini_file, config_path) then
      print("Config file created successfully")
    end
  end

  thread = love.thread.newThread("lib/backend.lua")
  thread:start()
  push_command(skyscraper.base_command .. "-v")
end

function skyscraper.change_artwork(artworkXml)
  local config = ini.load(skyscraper.config_path)
  if config then
    ini.addKey(config, "main", "artworkXml", '"' .. artworkXml .. '"')
    ini.save(config, skyscraper.config_path)
  end
end

function skyscraper.run(command)
  print("Running Skyscraper")
  push_command(skyscraper.base_command .. command)
end

function skyscraper.update_sample(artwork_path)
  print("Updating sample")
  skyscraper.custom_update_artwork("megadrive", work_dir .. "/sample", work_dir .. "/sample",
    artwork_path)
end

function skyscraper.custom_update_artwork(platform, cache, input, artwork)
  local command = "-p" .. platform .. " -d " ..
      cache .. " -i " .. input .. " -a " .. artwork .. " --flags unattend"
  skyscraper.run(command)
end

function skyscraper.fetch_artwork()
  local command = "-p snes -s " .. skyscraper.module .. " -c " .. skyscraper.config_path
  -- print(command)
  skyscraper.run(command)
end

function skyscraper.update_artwork(platform, artwork)
  local command = "-p" .. platform .. " -c " .. skyscraper.config_path .. " -a " .. artwork
  skyscraper.run(command)
end

return skyscraper
