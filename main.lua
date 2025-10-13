require("globals")
local log        = require("lib.log")
local pprint     = require("lib.pprint")

local scenes     = require("lib.scenes")
local skyscraper = require("lib.skyscraper")
local splash     = require("lib.splash")

local configs    = require("helpers.config")
local input      = require("helpers.input")
local utils      = require("helpers.utils")

log.start()

local user_config, skyscraper_config = configs.user_config, configs.skyscraper_config
local theme = configs.theme

local font = love.graphics.newFont(
  theme:read("main", "FONT") or "assets/ChakraPetch-Regular.ttf",
  theme:read_number("main", "FONT_SIZE") or 20)
love.graphics.setFont(font)

local footer = require("lib.gui.footer")()
local w_width, w_height = love.window.getMode()

function love.load(args)
  splash.load()

  if #args > 0 then
    local res = args[1]
    if res then
      _G.resolution = res
      res = utils.split(res, "x")
      love.window.setMode(tonumber(res[1]) or 640, tonumber(res[2]) or 480)
      w_width, w_height = love.window.getMode()
    end
  end


  -- Debug mode
  local debug = user_config:read("main", "debug")
  if debug ~= "1" then
    _G.print = function() end
    setmetatable(pprint, { __call = function() end })
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
    -- Draw footer on main scene; also on settings when no overlay (VK) is active
    local focus = scenes:currentFocus()
    if focus == "main" or (focus == "settings" and not (_G.ui_overlay_active or false)) then
      footer:draw()
    end
  end
end
