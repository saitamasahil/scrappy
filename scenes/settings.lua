local scenes            = require("lib.scenes")
local configs           = require("helpers.config")
local utils             = require("helpers.utils")

local component         = require 'lib.gui.badr'
local button            = require 'lib.gui.button'
local label             = require 'lib.gui.label'
local checkbox          = require 'lib.gui.checkbox'
local scroll_container  = require 'lib.gui.scroll_container'

local user_config       = configs.user_config
local theme             = configs.theme
local w_width, w_height = love.window.getMode()

local settings          = {}

local menu, checkboxes

local all_check         = true


local function on_filter_resolution(index)
  local filtering = user_config:read("main", "filterTemplates") == "1"
  user_config:insert("main", "filterTemplates", filtering and "0" or "1")
  user_config:save()
end

local function on_change_platform(platform)
  local selected_platforms = user_config:get().platformsSelected
  local checked = tonumber(selected_platforms[platform]) == 1
  user_config:insert("platformsSelected", platform, checked and "0" or "1")
  user_config:save()
end

local function update_checkboxes()
  checkboxes.children = {}
  local platforms = user_config:get().platforms
  -- local custom_platforms = user_config:get().platformsCustom
  local selected_platforms = user_config:get().platformsSelected
  for platform in utils.orderedPairs(platforms or {}) do
    checkboxes = checkboxes + checkbox {
      text = platform,
      id = platform,
      onToggle = function() on_change_platform(platform) end,
      checked = selected_platforms[platform] == "1"
    }
  end
  -- for custom in utils.orderedPairs(custom_platforms or {}) do
  --   checkboxes = checkboxes + checkbox {
  --     text = custom .. "*",
  --     id = custom,
  --     onToggle = function() on_change_platform(custom) end,
  --     checked = selected_platforms[custom] == "1"
  --   }
  -- end
end

local function on_refresh_press()
  user_config:load_platforms()
  user_config:save()
  update_checkboxes()
end

local on_check_all_press = function()
  local selected_platforms = user_config:get().platformsSelected
  for platform, checked in pairs(selected_platforms) do
    user_config:insert("platformsSelected", platform, all_check and "0" or "1")
  end
  all_check = not all_check
  user_config:save()
  update_checkboxes()
end

function settings:load()
  menu = component:root { column = true, gap = 10 }
  checkboxes = component { column = true, gap = 0 }

  menu = menu
      + label { text = 'Resolution', icon = "display" }
      + checkbox {
        text = 'Filter templates for my resolution',
        onToggle = on_filter_resolution,
        checked = user_config:read("main", "filterTemplates") == "1"
      }
      + label { text = 'Platforms', icon = "folder" }
      + (component { row = true, gap = 10 }
        + button { text = 'Rescan folders', width = 200, onClick = on_refresh_press }
        + button { text = 'Un/check all', width = 200, onClick = on_check_all_press })

  local menu_height = menu.height

  menu = menu
      + (scroll_container {
          width = w_width - 20,
          height = w_height - menu_height - 60,
          scroll_speed = 30,
        }
        + checkboxes)

  update_checkboxes()

  menu:updatePosition(10, 10)
  menu:focusFirstElement()
end

function settings:update(dt)
  menu:update(dt)
end

function settings:draw()
  love.graphics.clear(theme:read_color("main", "BACKGROUND", "#000000"))
  menu:draw()
end

function settings:keypressed(key)
  menu:keypressed(key)
  if key == "escape" or key == "lalt" then
    scenes:pop()
  end
end

return settings
