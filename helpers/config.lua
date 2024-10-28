local config = {
  type = "",
  path = "",
  values = {}
}
config.__index = config

local ini = require("lib.ini")
local nativefs = require("lib.nativefs")
local muos = require("muos")

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
  return ini.save(example, self.path) ~= nil
end

function config:read(section, key)
  return ini.readKey(self.values, section, key)
end

function config:insert(section, key, value)
  if self.values[section] == nil then
    self.values[section] = {}
  end
  ini.addKey(self.values, section, key, value)
end

function config:detect_sd()
  local sd1 = muos.SD1_PATH
  local sd2 = muos.SD2_PATH
  if nativefs.getInfo(sd2) then
    self:insert("main", "sd", 2)
    print("Found SD2")
  elseif nativefs.getInfo(sd1) then
    self:insert("main", "sd", 1)
    print("Found SD1")
  else
    print("No SD found")
  end
end

function config:load_platforms()
  if self.type == "skyscraper" then
    return
  end

  local sd = self:read("main", "sd")
  local rom_path = muos.SD1_PATH

  if sd == 2 then
    rom_path = muos.SD2_PATH
  end

  local platforms = nativefs.getDirectoryItems(rom_path)
  local mapped_total = 0

  if next(platforms) == nil then
    print("No platforms found")
    return
  end
  -- Iterate through platforms
  for i = 1, #platforms do
    local platform = platforms[i]:lower()
    -- Iterate through muos assign table
    for key, value in pairs(muos.assign) do
      if platform == key then
        self:insert("platforms", platforms[i], "\"" .. value .. "\"")
        mapped_total = mapped_total + 1
        break
      end
    end
  end
  print(string.format("Found %d platforms, mapped %d", #platforms, mapped_total))
end

return config
