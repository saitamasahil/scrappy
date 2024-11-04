local scenes = require("lib.scenes")
local ui = require("lib.ui")
local configs = require("helpers.config")

local user_config = configs.user_config

local main_ui = ui.new()
local padding = 10

local settings = {}
local w_width, w_height = love.window.getMode()

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

function settings:load()
end

function settings:update(dt)
  -- Root Layout
  main_ui:layout(0, 0, w_width, w_height, padding, padding)

  main_ui:layout(0, 0, w_width / 2, 30, 0, 5, "horizontal")
  main_ui:element({ 0, 0 }, ui.icon_label("Platforms", "controller"))
  main_ui:element({ 0, 0, 150, 30 }, ui.button("Refresh", on_refresh_press, "redo"))
  main_ui:end_layout()

  main_ui:layout(0, 20, w_width, w_height - 110, 0, 0)
  for platform, checked in pairs(user_config.values.selectedPlatforms or {}) do
    main_ui:element(
      { 0, 0, w_width / 2, 30 },
      ui.checkbox(platform, tonumber(checked) == 1, function() on_change_platform(platform) end)
    )
  end
  main_ui:end_layout()
  main_ui:end_layout() -- End root layout
end

function settings:draw()
  love.graphics.clear(0, 0, 0, 1)
  love.graphics.push()
  love.graphics.setColor(0, 0, 0, 1)
  main_ui:draw()
  love.graphics.pop()
end

function settings:keypressed(key)
  main_ui:keypressed(key)
  if key == "escape" then
    scenes:pop()
  end
end

return settings
