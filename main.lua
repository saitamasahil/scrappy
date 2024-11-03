local log = require("lib.log")
log.start()

require("globals")
local font = love.graphics.newFont("assets/monogram.ttf", 30)
love.graphics.setDefaultFilter("nearest", "nearest")
love.graphics.setFont(font)

local scenes = require("lib.scenes")
local skyscraper = require("lib.skyscraper")
local splash = require("lib.splash")
local input = require("helpers.input")
local configs = require("helpers.config")

local user_config, skyscraper_config = configs.user_config, configs.skyscraper_config

function love.load()
  splash.load()
  scenes:load("main")

  skyscraper.init(
    skyscraper_config.path,
    user_config:read("main", "binary") or "bin/Skyscraper.aarch64")
  input.load()

  -- local debug = user_config:read("main", "debug")
  -- if not debug or debug == 0 then
  --   function _G.print() end
  -- end
end

function love.update(dt)
  splash.update(dt)
  input.update(dt)
  scenes:update(dt)
  input.onEvent(function(key)
    scenes:keypressed(key)
  end)
end

function love.draw()
  love.graphics.setBackgroundColor(0, 0, 0, 1)
  splash.draw()

  if splash.finished then
    scenes:draw()
  end
end
