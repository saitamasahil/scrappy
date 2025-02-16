require("globals")

local log               = require("lib.log")
local channels          = require("lib.backend.channels")
local skyscraper_config = require("helpers.config").skyscraper_config

local skyscraper        = {
  base_command = "./Skyscraper",
  module = "screenscraper",
  config_path = "",
}

local cache_thread, gen_thread

local function push_cache_command(command)
  if channels.SKYSCRAPER_INPUT then
    channels.SKYSCRAPER_INPUT:push(command)
  end
end
local function push_command(command)
  if channels.SKYSCRAPER_GEN_INPUT then
    channels.SKYSCRAPER_GEN_INPUT:push(command)
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

  -- Create threads for cache and generate commands
  cache_thread = love.thread.newThread("lib/backend/skyscraper_backend.lua")
  gen_thread = love.thread.newThread("lib/backend/skyscraper_generate_backend.lua")

  cache_thread:start()
  gen_thread:start()
  push_cache_command({ command = string.format("%s -v", skyscraper.base_command), version = 1 })
end

local function generate_command(config)
  if config.fetch == nil then
    config.fetch = false
  end
  if config.use_config == nil then
    config.use_config = true
  end
  if config.module == nil then
    config.module = skyscraper.module
  end

  local command = ""
  if config.platform then
    command = string.format('%s -p %s', command, config.platform)
  end
  if config.fetch then
    command = string.format('%s -s %s', command, config.module)
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

  -- Force maximum number of threads
  command = string.format('%s -t 8', command)
  return command
end

function skyscraper.run(command, platform, op, game, ...)
  -- print("Running Skyscraper")
  platform = platform or "none"
  op = op or "generate"
  game = game or "none"
  local task_id = select(1, ...) or nil
  if op == "generate" then
    push_command({
      command = skyscraper.base_command .. command,
      platform = platform,
      op = op,
      game = game,
      task_id = task_id,
    })
  else
    push_cache_command({
      command = skyscraper.base_command .. command,
      platform = platform,
      op = op,
      game = game,
      task_id = task_id,
    })
  end
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

function skyscraper.fetch_artwork(rom_path, platform, ...)
  local command = generate_command({
    platform = platform,
    input = rom_path,
    fetch = true,
    flags = { "unattend", "onlymissing" },
  })
  skyscraper.run(command, platform, "update")
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
  local flags = select(2, ...) or { "unattend", "onlymissing" }
  local fetch_command = generate_command({
    platform = platform,
    input = rom_path,
    fetch = true,
    rom = rom,
    flags = flags,
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

function skyscraper.custom_import(rom_path, platform)
  local command = generate_command({
    platform = platform,
    input = rom_path,
    module = "import",
    fetch = true,
  })
  skyscraper.run(command, platform, "import")
end

return skyscraper
