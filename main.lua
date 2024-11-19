local log = require("lib.log")
log.start()

require("globals")
local font = love.graphics.newFont("assets/ChakraPetch-Regular.ttf", 20)
love.graphics.setFont(font)

local scenes = require("lib.scenes")
local skyscraper = require("lib.skyscraper")
local splash = require("lib.splash")
local input = require("helpers.input")
local configs = require("helpers.config")
local utils = require("helpers.utils")

local user_config, skyscraper_config = configs.user_config, configs.skyscraper_config

local footer = require("lib.gui.footer")()

local w_width, w_height

function love.load()
  splash.load()

  local res = user_config:read("main", "resolution")
  if res then
    res = utils.split(res, "x")
    love.window.setMode(tonumber(res[1]) or 640, tonumber(res[2]) or 480)
    w_width, w_height = love.window.getMode()
  end

  scenes:load("main")

  skyscraper.init(
    skyscraper_config.path,
    user_config:read("overrides", "binary") or "bin/Skyscraper.aarch64")
  input.load()

  footer:updatePosition(w_width * 0.5 - footer.width * 0.5 - 20, w_height - footer.height - 10)
end

function love.update(dt)
  timer.update(dt)
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
    footer:draw()
  end
end
