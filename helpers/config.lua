local log = require("lib.log")

local config = {
  type = "",
  path = "",
  values = {}
}
config.__index = config

local ini = require("lib.ini")
local nativefs = require("lib.nativefs")
local muos = require("helpers.muos")

function config.new(type, path)
  return setmetatable({ type = type or "user", path = path or "config.ini" }, config)
end

function config:load()
  local values = ini.load(self.path)
  if values ~= nil then
    self.values = values
  end
  return values ~= nil
end

function config:save()
  return ini.save(self.values, self.path)
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
  ini.addKey(self.values, section, key, value)
end

function config:get()
  return self.values
end

function config:detect_sd()
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

function config:get_paths()
  --[[
    Get paths from config
    Args:
      None
    Returns:
    (skyscraper)
      cache_path: string
      output_path: string
    (user)
      rom_path: string
      catalogue_path: string
  --]]
  if self.type == "skyscraper" then
    local cache_path = self:read("main", "cacheFolder")
    local output_path = self:read("main", "gameListFolder")
    return cache_path, output_path
  end
  -- Check for overrides
  local rom_path_override = self:read("overrides", "romPath")
  local catalogue_path_override = self:read("overrides", "cataloguePath")
  if rom_path_override ~= nil and catalogue_path_override ~= nil then
    return rom_path_override, catalogue_path_override
  end

  -- Get paths
  local sd = self:read("main", "sd")
  local rom_path = string.format("%s/roms", muos.SD2_PATH)
  local catalogue_path = string.format("%s/%s", muos.SD2_PATH, muos.CATALOGUE)
  if tonumber(sd) == 1 then
    rom_path = string.format("%s/ROMS", muos.SD1_PATH)
    catalogue_path = string.format("%s/%s", muos.SD1_PATH, muos.CATALOGUE)
  end

  -- Check for overrides
  if rom_path_override then rom_path = rom_path_override end
  if catalogue_path_override then catalogue_path = catalogue_path_override end
  return rom_path, catalogue_path
end

function config:load_platforms()
  if self.type == "skyscraper" then
    return
  end

  log.write("Loading platforms")

  local rom_path, _ = self:get_paths()

  local platforms = nativefs.getDirectoryItems(rom_path)
  local mapped_total = 0

  if next(platforms) == nil then
    log.write("No platforms found")
    return
  end
  -- Iterate through platforms
  for i = 1, #platforms do
    local platform = platforms[i]:lower()
    -- Iterate through muos assign table
    for key, value in pairs(muos.assign) do
      if platform == key then
        self:insert("platforms", platforms[i], value)
        mapped_total = mapped_total + 1
        break
      end
    end
  end
  log.write(string.format("Found %d platforms, mapped %d", #platforms, mapped_total))
end

return config
