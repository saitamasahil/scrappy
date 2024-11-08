require("globals")

local log = require("lib.log")
local skyscraper_config = require("helpers.config").skyscraper_config

local skyscraper = {
  base_command = "./Skyscraper",
  module = "screenscraper",
  config_path = "",
}

local thread

local function push_command(command)
  if INPUT_CHANNEL then
    INPUT_CHANNEL:push(command)
  end
end

function skyscraper.init(config_path, binary)
  log.write("Initializing Skyscraper")
  skyscraper.config_path = WORK_DIR .. "/" .. config_path
  skyscraper.base_command = "./" .. binary

  local quick_id = nativefs.read("sample/quickid.xml")
  if quick_id then
    -- print("Writing quickid.xml")
    quick_id = string.gsub(quick_id, "filepath=\"%S+\"", "filepath=\"" .. WORK_DIR .. "/sample/fake-rom.zip\"")
    quick_id = string.gsub(quick_id, "id=\"%S+\"", "id=\"fake-rom\"")
    nativefs.write("sample/quickid.xml", quick_id)
  end

  thread = love.thread.newThread("lib/backend.lua")
  thread:start()
  push_command({ command = string.format("%s -v", skyscraper.base_command), version = 1 })
end

local function generate_command(config)
  if config.fetch == nil then
    config.fetch = false
  end
  if config.use_config == nil then
    config.use_config = true
  end

  local command = ""
  if config.platform then
    command = string.format('%s -p %s', command, config.platform)
  end
  if config.fetch then
    command = string.format('%s -s %s', command, skyscraper.module)
  end
  if config.use_config then
    command = string.format('%s -c "%s"', command, skyscraper.config_path)
  end
  if config.cache then
    command = string.format('%s -d "%s"', command, config.cache)
  end
  if config.input then
    command = string.format('%s -i "%s"', command, config.input)
  end
  if config.rom then
    command = string.format('%s --startat "%s" --endat "%s"', command, config.rom, config.rom)
  end
  if config.artwork then
    command = string.format('%s -a "%s"', command, config.artwork)
  end
  if config.flags and next(config.flags) then
    command = string.format('%s --flags %s', command, table.concat(config.flags, ","))
  end
  return command
end

function skyscraper.run(command, platform, op, game, ...)
  -- print("Running Skyscraper")
  platform = platform or "none"
  op = op or "generate"
  game = game or "none"
  local task_id = select(1, ...) or nil
  push_command({
    command = skyscraper.base_command .. command,
    platform = platform,
    op = op,
    game = game,
    task_id = task_id,
  })
end

function skyscraper.change_artwork(artworkXml)
  skyscraper_config:insert("main", "artworkXml", '"' .. artworkXml .. '"')
  skyscraper_config:save()
end

function skyscraper.update_sample(artwork_path)
  local command = generate_command({
    use_config = false,
    platform = "megadrive",
    cache = WORK_DIR .. "/sample",
    input = WORK_DIR .. "/sample",
    artwork = artwork_path,
    flags = { "unattend" },
  })
  skyscraper.run(command, "N/A", "generate", "fake-rom")
end

function skyscraper.custom_update_artwork(platform, cache, input, artwork)
  local command = generate_command({
    use_config = false,
    platform = platform,
    cache = cache,
    input = input,
    artwork = artwork,
    flags = { "unattend" },
  })
  skyscraper.run(command)
end

function skyscraper.fetch_artwork(platform)
  local command = generate_command({
    platform = platform,
    fetch = true,
  })
  skyscraper.run(command)
end

function skyscraper.update_artwork(rom_path, rom, platform, artwork, ...)
  local artwork = WORK_DIR .. "/templates/" .. artwork .. ".xml"
  local task_id = select(1, ...) or rom
  local update_command = generate_command({
    platform = platform,
    input = rom_path,
    artwork = artwork,
    rom = rom,
  })
  skyscraper.run(update_command, platform, "generate", rom, task_id)
end

function skyscraper.fetch_and_update_artwork(rom_path, rom, platform, artwork, ...)
  local artwork = WORK_DIR .. "/templates/" .. artwork .. ".xml"
  local task_id = select(1, ...) or rom
  local fetch_command = generate_command({
    platform = platform,
    input = rom_path,
    fetch = true,
    rom = rom,
    flags = { "unattend", "onlymissing" },
  })
  local update_command = generate_command({
    platform = platform,
    input = rom_path,
    artwork = artwork,
    rom = rom,
  })
  skyscraper.run(fetch_command, platform, "fetch", rom)
  skyscraper.run(update_command, platform, "generate", rom, task_id)
end

return skyscraper
