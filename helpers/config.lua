require("globals")
local log      = require("lib.log")
local ini      = require("lib.ini")
local nativefs = require("lib.nativefs")
local muos     = require("helpers.muos")
local utils    = require("helpers.utils")

local config   = {}
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
  if not self:section_exists(section) then
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

function user_config:start_fresh()
  if self:create_from("config.ini.example") then
    log.write("Created user config")
    self:detect_sd()
    self:load_platforms()
    self:save()
  else
    log.write("Failed to create user config")
  end
end

function user_config:init()
  if self:load() then
    log.write("Loaded user config")
    -- Fill defaults if missing
    self:fill_defaults()
  else
    self:start_fresh()
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

  if not self:read("main", "accentSource") then
    self:insert("main", "accentSource", "muos")
  end
  if not self:read("main", "customAccent") then
    self:insert("main", "customAccent", "cbaa0f")
  end

  if not self:read("main", "accentMode") then
    local saved_muos = self:read("main", "muosAccent")
    local muos_on = (saved_muos == nil) or (saved_muos ~= "0")
    if not muos_on then
      self:insert("main", "accentMode", "off")
    else
      local src = tostring(self:read("main", "accentSource") or "muos"):lower()
      self:insert("main", "accentMode", (src == "custom") and "custom" or "muos")
    end
  end
  self:save()
end

function user_config:detect_sd()
  log.write("Detecting SD storage preference")

  -- Detect SD2 ROMs
  local rom_folder = ""
  for _, item in ipairs(nativefs.getDirectoryItems(muos.SD2_PATH) or {}) do
    if item:lower() == "roms" then
      rom_folder = item
      break
    end
  end
  if rom_folder ~= "" and #nativefs.getDirectoryItems(string.format("%s/%s", muos.SD2_PATH, rom_folder)) > 0 then
    self:insert("main", "sd", 2)
    log.write("Found SD2")
    return
  end

  log.write("No SD2 found. Defaulting to SD1")
  self:insert("main", "sd", 1)
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

  local catalogue_path = muos.CATALOGUE
  local rom_path

  -- Try MuOS union mount first (handles USB->SD2->SD1 priority automatically)
  local union_roms_path = muos.UNION_PATH .. "/ROMS"
  if nativefs.getInfo(union_roms_path) then
    return union_roms_path, catalogue_path
  end

  -- Fallback to legacy SD detection for compatibility
  local sd = self:read("main", "sd")
  rom_path = sd == "1" and muos.SD1_PATH or muos.SD2_PATH
  for _, item in ipairs(nativefs.getDirectoryItems(rom_path) or {}) do
    if item:lower() == "roms" then
      rom_path = string.format("%s/%s", rom_path, item)
      break
    end
  end

  return rom_path_override or rom_path, catalogue_path_override or catalogue_path
end

function user_config:load_platforms()
  local rom_path, _ = self:get_paths()

  log.write(string.format("Loading platforms from %s", rom_path))

  -- Function to parse core.cfg files
  local function parse_dir(cfg_file)
    local lines = {}
    for line in cfg_file:gmatch("[^\r\n]+") do
      table.insert(lines, line)
    end
    if #lines < 3 then
      return nil, "Error parsing cfg file"
    end
    return lines[2], nil
  end

  -- Recursive function to scan directories
  local function scan_directories(base_path, relative_path)
    local platforms = {}
    local contains_files = false
    local items = nativefs.getDirectoryItems(base_path)

    for _, item in ipairs(items) do
      local item_path = base_path .. "/" .. item
      local file_info = nativefs.getInfo(item_path)

      -- Ignore hidden folders and files
      if file_info and file_info.type == "directory" and item:sub(1, 1) ~= "." then
        -- Construct the relative path for the current directory
        local current_relative_path = relative_path and (relative_path .. "/" .. item) or item

        -- Recursively collect platforms from subdirectories
        local sub_platforms = scan_directories(item_path, current_relative_path)
        for _, sub_platform in ipairs(sub_platforms) do
          table.insert(platforms, sub_platform)
        end
      elseif file_info and file_info.type == "file" then
        contains_files = true
      end
    end

    -- Add current folder to platforms if it contains files
    if contains_files and relative_path then
      table.insert(platforms, relative_path)
    end

    return platforms, contains_files
  end

  -- Scan the main ROM path for platforms
  local platforms = scan_directories(rom_path, nil)
  if not platforms or next(platforms) == nil then
    log.write("No platforms found")
    return
  end

  ini.deleteSection(self.values, "platforms")
  ini.deleteSection(self.values, "platformsSelected")

  local inserted = {}
  for _, item in ipairs(platforms) do
    -- Use leaf folder for core assignment (so nested like "Consoles/nes" resolves to "nes")
    local leaf = tostring(item):match("[^/]+$") or tostring(item)
    -- Also get parent folder for inheritance (e.g., "GBA" from "GBA/Homebrew")
    local parent = tostring(item):match("^([^/]+)/") or nil
    local assignment = nil

    -- Helper function to try reading core.cfg from a path and get assignment
    local function try_core_cfg(core_base_path, folder_name_to_check)
      local core_path = core_base_path .. "/" .. folder_name_to_check .. "/core.cfg"
      local core_info = nativefs.getInfo(core_path)
      if core_info then
        local file = nativefs.read(core_path)
        if file then
          local folder_name, err = parse_dir(file)
          if not err and folder_name then
            local result = muos.assignment[folder_name]
            -- Fallback for cores with different labels (e.g., DOSBox Pure, blueMSX)
            if not result then
              local fn = tostring(folder_name):lower()
              if fn:find("dosbox") then result = "pc" end
              if fn:find("msx") or fn:find("bluemsx") then result = "msx" end
            end
            return result
          end
        end
      end
      return nil
    end

    -- 1. Attempt to resolve via muOS core.cfg
    -- MuOS stores core assignments at /opt/muos/share/info/core/ with full folder path
    -- e.g., /opt/muos/share/info/core/Atari Collection/Atari 5200/core.cfg
    -- Check FULL folder path first (for nested folders like "Atari Collection/Atari 5200")
    assignment = try_core_cfg(muos.CORE_DIR, item)
    -- Then try just the leaf folder name (for simple folders like "NES")
    if not assignment then
      assignment = try_core_cfg(muos.CORE_DIR, leaf)
    end

    -- 1b. If still no assignment and this is a subfolder, try PARENT folder's core.cfg
    if not assignment and parent then
      assignment = try_core_cfg(muos.CORE_DIR, parent)
      if assignment then
        log.write(string.format("Inherited platform '%s' for '%s' from parent folder '%s'", assignment, item, parent))
      end
    end

    -- 2. Fallback: infer assignment by matching LEAF folder name to muOS platform labels or keys (case-insensitive)
    if not assignment then
      local item_l = tostring(leaf):lower()
      -- Heuristic shortcuts and common aliases for folder names
      local alias = {
        ["pc"] = "pc",
        ["dos"] = "pc",
        ["dosgames"] = "pc",
        ["arcade"] = "arcade",
        ["mame"] = "arcade",
        ["genesis"] = "megadrive",
        ["md"] = "megadrive",
        ["smd"] = "megadrive",
        ["megadrive"] = "megadrive",
        ["sms"] = "mastersystem",
        ["mastersystem"] = "mastersystem",
        ["sg-1000"] = "sg-1000",
        ["sg1000"] = "sg-1000", -- legacy alias
        ["gg"] = "gamegear",
        ["gamegear"] = "gamegear",
        ["pce"] = "pcengine",
        ["pcengine"] = "pcengine",
        ["pcecd"] = "pcenginecd",
        ["pcenginecd"] = "pcenginecd",
        ["supergrafx"] = "pcengine_",
        ["fds"] = "fds",
        ["nes"] = "nes",
        ["snes"] = "snes",
        ["n64"] = "n64",
        ["psx"] = "psx",
        ["ps1"] = "psx",
        ["psx-multi"] = "psx",
        ["psp"] = "psp",
        ["ngp"] = "ngp",
        ["ngpc"] = "ngpc",
        ["32x"] = "sega32x",
        ["sega32x"] = "sega32x",
        ["segacd"] = "segacd",
        ["megacd"] = "segacd",
        ["cd-i"] = "cdi",
        ["gamecube"] = "gc",
        ["gc"] = "gc",
        ["nintendo gamecube"] = "gc",
      }
      if alias[item_l] then assignment = alias[item_l] end
      -- Exact key/label match
      if not assignment then
        for key, label in pairs(muos.platforms or {}) do
          if type(label) == "string" then
            local key_l = tostring(key):lower()
            local label_l = label:lower()
            if label_l == item_l or key_l == item_l then
              assignment = key
              break
            end
          end
        end
      end
      -- Partial label contains match (e.g., leaf "genesis" in label "Sega Mega Drive - Genesis")
      if not assignment then
        for key, label in pairs(muos.platforms or {}) do
          if type(label) == "string" then
            local label_l = label:lower()
            if label_l:find(item_l, 1, true) then
              assignment = key
              break
            end
          end
        end
      end
      if assignment then
        log.write(string.format("Inferred platform '%s' for folder '%s' via leaf label match", assignment, item))
      end
    end

    -- 2b. Fallback: if still no assignment and has parent, try parent folder name against aliases
    if not assignment and parent then
      local parent_l = tostring(parent):lower()
      local alias = {
        ["gba"] = "gba",
        ["gbc"] = "gbc",
        ["gb"] = "gb",
        ["nes"] = "nes",
        ["snes"] = "snes",
        ["n64"] = "n64",
        ["nds"] = "nds",
        ["psx"] = "psx",
        ["psp"] = "psp",
        ["genesis"] = "megadrive",
        ["megadrive"] = "megadrive",
        ["arcade"] = "arcade",
        ["mame"] = "arcade",
      }
      if alias[parent_l] then
        assignment = alias[parent_l]
        log.write(string.format("Inherited platform '%s' for '%s' from parent folder alias", assignment, item))
      end
      -- Also try muos.platforms lookup for parent
      if not assignment then
        for key, label in pairs(muos.platforms or {}) do
          if type(label) == "string" then
            local key_l = tostring(key):lower()
            local label_l = label:lower()
            if label_l:find(parent_l, 1, true) or key_l == parent_l then
              assignment = key
              log.write(string.format("Inherited platform '%s' for '%s' from parent folder '%s'", assignment, item, parent))
              break
            end
          end
        end
      end
    end

    -- 3. Refine assignment using file content heuristics
    if assignment then
      -- Heuristic override: if core assignment is GB but folder contains GBC roms, treat as GBC
      if assignment == "gb" then
        local platform_path = string.format("%s/%s", rom_path, item)
        local files = nativefs.getDirectoryItems(platform_path) or {}
        for _, f in ipairs(files) do
          if f:lower():match("%.gbc$") then
            assignment = "gbc"
            break
          end
        end
      end
      -- Heuristic override: Wonderswan vs Wonderswan Color
      if assignment == "wonderswancolor" then
        local platform_path = string.format("%s/%s", rom_path, item)
        local files = nativefs.getDirectoryItems(platform_path) or {}
        local has_ws, has_wsc = false, false
        for _, f in ipairs(files) do
          local fl = f:lower()
          if fl:match("%.ws$") then has_ws = true end
          if fl:match("%.wsc$") then has_wsc = true end
          if has_wsc then break end
        end
        if has_ws and not has_wsc then
          assignment = "wonderswan"
        end
      end
      -- Heuristic override: Neo Geo Pocket vs Neo Geo Pocket Color
      if assignment == "ngpc" then
        local platform_path = string.format("%s/%s", rom_path, item)
        local files = nativefs.getDirectoryItems(platform_path) or {}
        local has_ngp, has_ngpc_like = false, false
        for _, f in ipairs(files) do
          local fl = f:lower()
          if fl:match("%.ngp$") then has_ngp = true end
          if fl:match("%.ngc$") or fl:match("%.ngpc$") then has_ngpc_like = true end
          if has_ngpc_like then break end
        end
        if has_ngp and not has_ngpc_like then
          assignment = "ngp"
        end
      end
      -- Heuristic override: SG-1000 vs Master System
      if assignment == "mastersystem" then
        local platform_path = string.format("%s/%s", rom_path, item)
        local files = nativefs.getDirectoryItems(platform_path) or {}
        for _, f in ipairs(files) do
          if f:lower():match("%.sg$") then
            assignment = "sg-1000"
            break
          end
        end
      end
      -- Heuristic override: Umbrella 'coleco' (MSX-SVI-ColecoVision-SG1000) -> specialize based on files/folder
      if assignment == "coleco" then
        local platform_path = string.format("%s/%s", rom_path, item)
        local files = nativefs.getDirectoryItems(platform_path) or {}
        local has_msx_like, has_sg = false, false
        for _, f in ipairs(files) do
          local fl = f:lower()
          if fl:match("%.mx1$") or fl:match("%.mx2$") or fl:match("%.dsk$") or fl:match("%.cas$") then
            has_msx_like = true
            break
          end
          if fl:match("%.sg$") then
            has_sg = true
          end
        end
        if tostring(item):lower() == "msx" or has_msx_like then
          assignment = "msx"
        elseif has_sg then
          assignment = "sg-1000"
        end
      end
    end

    -- 4. Save to config
    local key = item
    if not inserted[key] then
      if assignment then
        self:insert("platforms", key, assignment)
        self:insert("platformsSelected", key, 1)
      else
        log.write(string.format("Unable to find platform for %s", item))
        self:insert("platforms", key, "unmapped")
        self:insert("platformsSelected", key, 0)
      end
      inserted[key] = true
    end
  end

  -- Ensure selected flags are populated for any new platforms
  self:fill_selected_platforms()
end

function user_config:fill_selected_platforms()
  for platform in utils.orderedPairs(self:get().platforms or {}) do
    if not self:read("platformsSelected", platform) then
      self:insert("platformsSelected", platform, 0)
    end
  end
end

function user_config:has_platforms()
  local platforms = self:get().platforms

  if not platforms then return false end

  local count = 0
  for _ in pairs(platforms) do
    count = count + 1
  end

  return count > 0
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

function skyscraper_config:start_fresh()
  if self:create_from("skyscraper_config.ini.example") then
    log.write("Created skyscraper config")
    self:reset()
  else
    log.write("Failed to create skyscraper config")
  end
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
      self:insert("main", "gameListFolder", string.format("\"%s/%s\"", WORK_DIR, "data/output"))
    end
    local region_prios = self:read("main", "regionPrios")
    if not region_prios or region_prios == "\"\"" then
      self:insert("main", "regionPrios",
        "\"us,wor,eu,jp,ss,uk,au,ame,de,cus,cn,kr,asi,br,sp,fr,gr,it,no,dk,nz,nl,pl,ru,se,tw,ca\"")
    end
    local subdirs = self:read("main", "subdirs")
    if not subdirs or subdirs == "\"\"" then
      self:insert("main", "subdirs", "\"false\"")
    end
  else
    self:start_fresh()
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

-- Theme specific
local theme   = setmetatable({}, { __index = config })
theme.__index = theme

-- Current active theme name and muOS accent state
local current_theme_name = "dark"
local muos_accent_enabled = true

-- Singleton instances (must be initialized before theme.create uses them)
local user_config_instance
local skyscraper_config_instance

local function clamp01(x)
  if x < 0 then return 0 end
  if x > 1 then return 1 end
  return x
end

local function hex_to_rgb01(hex)
  local h = tostring(hex or ""):gsub("#", "")
  if #h == 3 then
    h = h:sub(1,1)..h:sub(1,1)..h:sub(2,2)..h:sub(2,2)..h:sub(3,3)..h:sub(3,3)
  end
  if #h ~= 6 then return nil end
  local r = tonumber(h:sub(1,2), 16)
  local g = tonumber(h:sub(3,4), 16)
  local b = tonumber(h:sub(5,6), 16)
  if not r or not g or not b then return nil end
  return r/255, g/255, b/255
end

local function rgb01_to_hsl(r, g, b)
  local maxc = math.max(r, g, b)
  local minc = math.min(r, g, b)
  local l = (maxc + minc) / 2
  if maxc == minc then
    return 0, 0, l
  end
  local d = maxc - minc
  local s
  if l > 0.5 then s = d / (2 - maxc - minc) else s = d / (maxc + minc) end
  local h
  if maxc == r then
    h = (g - b) / d + (g < b and 6 or 0)
  elseif maxc == g then
    h = (b - r) / d + 2
  else
    h = (r - g) / d + 4
  end
  h = h / 6
  return h, s, l
end

local function hue2rgb(p, q, t)
  if t < 0 then t = t + 1 end
  if t > 1 then t = t - 1 end
  if t < 1/6 then return p + (q - p) * 6 * t end
  if t < 1/2 then return q end
  if t < 2/3 then return p + (q - p) * (2/3 - t) * 6 end
  return p
end

local function hsl_to_rgb01(h, s, l)
  if s == 0 then
    return l, l, l
  end
  local q
  if l < 0.5 then q = l * (1 + s) else q = l + s - l * s end
  local p = 2 * l - q
  local r = hue2rgb(p, q, h + 1/3)
  local g = hue2rgb(p, q, h)
  local b = hue2rgb(p, q, h - 1/3)
  return r, g, b
end

local function mk_color(r, g, b)
  return { clamp01(r), clamp01(g), clamp01(b), 1 }
end

local function build_material_overrides(seed_hex, theme_name)
  local r, g, b = hex_to_rgb01(seed_hex)
  if not r then return nil end
  local h, s, l = rgb01_to_hsl(r, g, b)
  s = clamp01(math.max(0.45, math.min(s, 0.65)))

  local focus_l = (theme_name == "light") and 0.72 or 0.30
  local container_l = (theme_name == "light") and 0.88 or 0.24

  local fr, fg, fb = hsl_to_rgb01(h, s, focus_l)
  local cr, cg, cb = hsl_to_rgb01(h, s * 0.40, container_l)

  local focus = mk_color(fr, fg, fb)
  local container = mk_color(cr, cg, cb)

  return {
    button = {
      BUTTON_FOCUS = focus,
    },
    select = {
      SELECT_FOCUS = focus,
    },
    listitem = {
      ITEM_FOCUS = focus,
    },
    checkbox = {
      CHECKBOX_FOCUS = focus,
      CHECKBOX_INDICATOR_BG = focus,
    },
    keyboard = {
      KEY_FOCUS = focus,
    },
  }
end

function theme.create(theme_name, muos_accent)
  theme_name = theme_name or "dark"
  muos_accent = muos_accent ~= false  -- default to true
  current_theme_name = theme_name
  muos_accent_enabled = muos_accent
  
  -- Select theme file based on dark/light and muOS accent on/off
  local filename
  if theme_name == "light" then
    filename = muos_accent and "theme_light.ini" or "theme_light_classic.ini"
  else
    filename = muos_accent and "theme.ini" or "theme_classic.ini"
  end
  
  local self = config.new("theme", filename)
  setmetatable(self, theme)
  self:init()

  self._material_overrides = nil
  if muos_accent_enabled then
    local mode = tostring(user_config_instance:read("main", "accentMode") or "muos"):lower()
    local src = user_config_instance:read("main", "accentSource") or "muos"
    local custom = user_config_instance:read("main", "customAccent") or "cbaa0f"
    local seed
    if mode == "custom" or tostring(src):lower() == "custom" then
      seed = custom
    else
      seed = self:read("button", "BUTTON_FOCUS") or self:read("listitem", "ITEM_FOCUS") or "cbaa0f"
    end
    self._material_overrides = build_material_overrides(seed, theme_name)
  end
  return self
end

function theme:init()
  if self:load() then
    log.write("Loaded theme config: " .. current_theme_name .. " (muOS accent: " .. tostring(muos_accent_enabled) .. ")")
  else
    log.write("Failed to load theme config")
  end
end

function theme:read_color(section, key, fallback)
  if self._material_overrides and self._material_overrides[section] and self._material_overrides[section][key] then
    return self._material_overrides[section][key]
  end
  local color = self:read(section, key)
  if not color then return utils.hex(fallback) end
  return utils.hex_v(color)
end

function theme:read_number(section, key, fallback)
  local number = self:read(section, key)
  return number and tonumber(number) or fallback
end

function theme:get_current_name()
  return current_theme_name
end

function theme:is_muos_accent()
  return muos_accent_enabled
end

-- Singleton instances
user_config_instance = user_config.create("config.ini")
skyscraper_config_instance = skyscraper_config.create("skyscraper_config.ini")

-- Load theme based on saved preferences
local saved_theme = user_config_instance:read("main", "theme") or "dark"
local saved_mode = tostring(user_config_instance:read("main", "accentMode") or ""):lower()
local muos_on
if saved_mode == "off" then
  muos_on = false
elseif saved_mode == "muos" or saved_mode == "custom" then
  muos_on = true
else
  local saved_muos = user_config_instance:read("main", "muosAccent")
  muos_on = saved_muos ~= "0"  -- default to true (ON)
end
local theme_instance = theme.create(saved_theme, muos_on)

-- Proxy object that always points to the current theme_instance
local proxy_theme = setmetatable({}, {
  __index = function(t, k)
    return theme_instance[k]
  end
})

local exports = {
  user_config = user_config_instance,
  skyscraper_config = skyscraper_config_instance,
  theme = proxy_theme, -- Export the proxy instead of the instance
}

function exports.reload_theme(theme_name, muos_accent)
  -- Update the internal instance; the proxy will see the new one
  theme_instance = theme.create(theme_name, muos_accent)
  return theme_instance
end

return exports

