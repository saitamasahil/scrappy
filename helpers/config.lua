local log = require("lib.log")
local ini = require("lib.ini")
local nativefs = require("lib.nativefs")
local muos = require("helpers.muos")
local utils = require("helpers.utils")

local config = {}
config.__index = config

function config.new(type, path)
  return setmetatable({ type = type, path = path, values = {} }, config)
end

function config:load()
  local values = ini.load(self.path)
  if values ~= nil then
    self.values = values
  end
  return values ~= nil
end

function config:save()
  return ini.save_ordered(self.values, self.path)
end

function config:create_from(example_file)
  local example = ini.load(example_file)
  if ini.save(example, self.path) ~= nil then
    self.values = example
    return 1
  end

  return nil
end

function config:read(section, key)
  if self.values[section] == nil then
    return nil
  end
  return ini.readKey(self.values, section, key)
end

function config:insert(section, key, value)
  if self.values[section] == nil then
    self.values[section] = {}
  end
  ini.addKey(self.values, section, key, tostring(value))
end

function config:section_exists(section)
  return self.values[section] ~= nil
end

function config:get()
  return self.values
end

-- User-specific config
local user_config = setmetatable({}, { __index = config })
user_config.__index = user_config

function user_config.create(config_path)
  local self = config.new("user", config_path or "config.ini")
  setmetatable(self, user_config)
  self:init()
  return self
end

function user_config:init()
  if self:load() then
    log.write("Loaded user config")
    -- Fill defaults if missing
    self:fill_defaults()
  else
    if self:create_from("config.ini.example") then
      log.write("Created user config")
      self:detect_sd()
      self:load_platforms()
      self:save()
    else
      log.write("Failed to create user config")
    end
  end
end

function user_config:fill_defaults()
  self:fill_selected_platforms()
  if not self:read("main", "sd") then
    self:detect_sd()
  end
  if not self:read("main", "parseCache") then
    self:insert("main", "parseCache", 1)
  end
  if not self:read("main", "filterTemplates") then
    self:insert("main", "filterTemplates", 1)
  end
  self:save()
end

function user_config:detect_sd()
  log.write("Detecting SD storage preference")
  local sd1 = muos.SD1_PATH
  local sd2 = muos.SD2_PATH
  if #nativefs.getDirectoryItems(sd2) > 0 then
    self:insert("main", "sd", 2)
    log.write("Found SD2")
  elseif #nativefs.getDirectoryItems(sd1) > 0 then
    self:insert("main", "sd", 1)
    log.write("Found SD1")
  else
    log.write("No SD found")
    return
  end
end

function user_config:get_paths()
  --[[
    Get paths from config
    Args:
      None
    Returns:
    (user)
      rom_path: string
      catalogue_path: string
  --]]
  -- Check for overrides
  local rom_path_override = self:read("overrides", "romPath")
  local catalogue_path_override = self:read("overrides", "cataloguePath")
  if rom_path_override and catalogue_path_override then
    return rom_path_override, catalogue_path_override
  end

  -- Get paths
  local sd = self:read("main", "sd")
  local rom_path = sd == "1" and string.format("%s/ROMS", muos.SD1_PATH) or string.format("%s/roms", muos.SD2_PATH)
  local catalogue_path = muos.CATALOGUE

  return rom_path_override or rom_path, catalogue_path_override or catalogue_path
end

function user_config:load_platforms()
  local rom_path, _ = self:get_paths()

  log.write(string.format("Loading platforms from %s", rom_path))

  local platforms = nativefs.getDirectoryItems(rom_path)
  local mapped_total = 0

  if not platforms or next(platforms) == nil then
    log.write("No platforms found")
    return
  end

  ini.deleteSection(self.values, "platforms")
  -- ini.deleteSection(self.values, "selectedPlatforms")

  -- Iterate through platforms
  for _, platform in ipairs(platforms) do
    local lower_platform = platform:lower()
    if muos.assign[lower_platform] then
      self:insert("platforms", platform, muos.assign[lower_platform])
      self:insert("platformsSelected", platform, 1)
      mapped_total = mapped_total + 1
    else
      log.write(string.format("Unable to automatically map platform for %s", platform))
      if not self:read("platformsCustom", platform) then
        self:insert("platformsCustom", platform, "unmapped")
        self:insert("platformsSelected", platform, 0)
      end
    end
  end
  log.write(string.format("Found %d platforms, mapped %d", #platforms, mapped_total))
end

function user_config:fill_selected_platforms()
  local platforms = utils.tableMerge(self:get().platforms, self:get().platformsCustom)
  for platform in utils.orderedPairs(platforms or {}) do
    if not self:read("platformsSelected", platform) then
      self:insert("platformsSelected", platform, 0)
    end
  end
end

-- Skyscraper-specific config
local skyscraper_config = {}
skyscraper_config.__index = skyscraper_config
setmetatable(skyscraper_config, { __index = config })

function skyscraper_config.create(config_path)
  local self = config.new("skyscraper", config_path or "skyscraper_config.ini")
  setmetatable(self, skyscraper_config)
  self:init()
  return self
end

function skyscraper_config:init()
  if self:load() then
    log.write("Loaded skyscraper config")
    local artwork_xml = self:read("main", "artworkXml")
    if not artwork_xml or artwork_xml == "\"\"" then
      self:insert("main", "artworkXml", string.format("\"%s/%s\"", WORK_DIR, "templates/box2d.xml"))
    end
    local cache_path = self:read("main", "cacheFolder")
    if not cache_path or cache_path == "\"\"" then
      self:insert("main", "cacheFolder", string.format("\"%s/%s\"", WORK_DIR, "data/cache"))
    end
    local output_path = self:read("main", "gameListFolder")
    if not output_path or output_path == "\"\"" then
      self:insert("main", "cacheFolder", string.format("\"%s/%s\"", WORK_DIR, "data/output"))
    end
  else
    if self:create_from("skyscraper_config.ini.example") then
      log.write("Created skyscraper config")
      self:reset()
    else
      log.write("Failed to create skyscraper config")
    end
  end
end

function skyscraper_config:reset()
  self:insert("main", "cacheFolder", string.format("\"%s/%s\"", WORK_DIR, "data/cache"))
  self:insert("main", "gameListFolder", string.format("\"%s/%s\"", WORK_DIR, "data/output"))
  self:insert("main", "artworkXml", string.format("\"%s/%s\"", WORK_DIR, "templates/box2d.xml"))
  self:save()
end

function skyscraper_config:has_credentials()
  local creds = self:read("screenscraper", "userCreds")
  return creds and creds:find("USER:PASS") == nil
end

function skyscraper_config:get_paths()
  local cache_path = self:read("main", "cacheFolder")
  local output_path = self:read("main", "gameListFolder")
  return cache_path, output_path
end

-- Singleton instances
local user_config_instance = user_config.create("config.ini")
local skyscraper_config_instance = skyscraper_config.create("skyscraper_config.ini")

return {
  user_config = user_config_instance,
  skyscraper_config = skyscraper_config_instance
}
