local scenes = require("lib.scenes")
local configs = require("helpers.config")

local user_config = configs.user_config

local settings = {}

local function on_refresh_press()
  user_config:load_platforms()
  user_config:save()
end

local function on_change_platform(platform)
  local selected_platforms = user_config.values.selectedPlatforms
  local checked = tonumber(selected_platforms[platform]) == 1
  user_config:insert("selectedPlatforms", platform, checked and "0" or "1")
  user_config:save()
end

local component = require 'lib.gui.badr'
local button    = require 'lib.gui.button'
local label     = require 'lib.gui.label'
local checkbox  = require 'lib.gui.checkbox'
local menu

function settings:load()
  menu = component { column = true, gap = 10 }
      + label { text = 'Platforms' }
      + button { text = 'Refresh', width = 200, onClick = on_refresh_press }
  local checkbox_list = component { column = true, gap = 0 }
  for platform, checked in pairs(user_config.values.selectedPlatforms or {}) do
    checkbox_list = checkbox_list +
        checkbox { text = platform, onToggle = function() on_change_platform(platform) end, checked = tonumber(checked) == 1 }
  end
  menu = menu + checkbox_list

  menu:updatePosition(
    10,
    10
  )
end

function settings:update(dt)
  menu:update(dt)
end

function settings:draw()
  love.graphics.clear(0, 0, 0, 1)
  menu:draw()
end

function settings:keypressed(key)
  menu:keypressed(key)
  if key == "escape" then
    scenes:pop()
  end
end

return settings
