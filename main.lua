require("globals")
local font = love.graphics.newFont("assets/monogram.ttf", 30)
love.graphics.setDefaultFilter("nearest", "nearest")
love.graphics.setFont(font)

local scenes = require("lib.scenes")
local skyscraper = require("lib.skyscraper")
local splash = require("lib.splash")
local input = require("helpers.input")
local config = require("helpers.config")
local muos = require("helpers.muos")

-- TODO: share config states between screens
local skyscraper_binary = "bin/Skyscraper.aarch64"
local user_config = config.new("user", "config.ini")
local skyscraper_config = config.new("skyscraper", "skyscraper_config.ini")

local function setup_configs()
  local rom_path = muos.SD1_PATH
  if user_config:load() then
    skyscraper_binary = user_config:read("main", "binary") or skyscraper_binary
    if user_config:read("main", "sd") == 2 then rom_path = muos.SD2_PATH end
  else
    local loaded = user_config:create_from("config.ini.example")
    if loaded then
      user_config:insert("main", "binary", skyscraper_binary)
      user_config:detect_sd()
      user_config:load_platforms()
      user_config:save()
    end
  end

  if not skyscraper_config:load() then
    local loaded = skyscraper_config:create_from("skyscraper_config.ini.example")
    if loaded then
      print("Config file not present, creating one")
      skyscraper_config:insert("main", "inputFolder", string.format("\"%s\"", rom_path))
      skyscraper_config:insert("main", "cacheFolder", string.format("\"%s/%s\"", WORK_DIR, "data/cache"))
      skyscraper_config:insert("main", "gameListFolder", string.format("\"%s/%s\"", WORK_DIR, "data/output"))
      skyscraper_config:insert("main", "artworkXml", string.format("\"%s/%s\"", WORK_DIR, "templates/box2d.xml"))
      skyscraper_config:save()
    end
  end
end

function love.load()
  splash.load()
  scenes:load("main")

  setup_configs()
  skyscraper.init(
    skyscraper_config,
    skyscraper_config.path,
    skyscraper_binary)
  input.load()

  local debug = user_config:read("main", "debug")
  if not debug or debug == 0 then
    function _G.print() end
  end
end

function love.update(dt)
  splash.update(dt)
  input.update(dt)
  scenes:update(dt)
end

function love.draw()
  love.graphics.setBackgroundColor(0, 0, 0, 1)
  splash.draw()

  if splash.finished then
    scenes:draw()
  end
end
