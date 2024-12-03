local log = require("lib.log")
log.start()

local configs = require("helpers.config")
local user_config, skyscraper_config = configs.user_config, configs.skyscraper_config
local theme = configs.theme

require("globals")

local font = love.graphics.newFont(
  theme:read("main", "FONT") or "assets/ChakraPetch-Regular.ttf",
  theme:read_number("main", "FONT_SIZE") or 20)

love.graphics.setFont(font)

local scenes = require("lib.scenes")
local skyscraper = require("lib.skyscraper")
local splash = require("lib.splash")
local input = require("helpers.input")
local utils = require("helpers.utils")

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
  splash.draw()

  if splash.finished then
    scenes:draw()
    footer:draw()
  end
end
