local scenes            = require("lib.scenes")
local configs           = require("helpers.config")
local utils             = require("helpers.utils")

local component         = require 'lib.gui.badr'
local button            = require 'lib.gui.button'
local label             = require 'lib.gui.label'
local popup             = require 'lib.gui.popup'
local select            = require 'lib.gui.select'
local checkbox          = require 'lib.gui.checkbox'
local scroll_container  = require 'lib.gui.scroll_container'

local user_config       = configs.user_config
local w_width, w_height = love.window.getMode()

local tools             = {}

local menu, info_window

local function toggle_info()
  info_window.visible = not info_window.visible
end
local function dispatch_info(title, content)
  info_window.title = title
  info_window.content = content
end

local function on_refresh_press()
  user_config:load_platforms()
  user_config:save()
end

function tools:load()
  menu = component:root { column = true, gap = 15 }
  info_window = popup { visible = false }

  menu = menu
      + (component { column = true, gap = 0 }
        + label { text = 'Scans ROMs folders, mapping platforms if found.', icon = "folder" }
        + button { text = 'Rescan folders', width = 200, onClick = on_refresh_press })
      + (component { column = true, gap = 0 }
        + label { text = 'Updates cache, not generating artwork.', icon = "sd_card" }
        + button { text = 'Update cache', width = 200, onClick = function() end })
      + (component { column = true, gap = 0 }
        + label { text = 'Imports custom data to cache. Read Wiki for more info.', icon = "file_import" }
        + button { text = 'Run custom import', width = 200, onClick = function() end })
      + (component { column = true, gap = 0 }
        + label { text = 'Resets user and Skyscraper configs. Can\'t be undone.', icon = "refresh" }
        + button { text = 'Reset configs', width = 200, onClick = function() end })
      + (component { column = true, gap = 0 }
        + label { text = 'Completely cleans resource cache. Can\'t be undone.', icon = "warn" }
        + button { text = 'Purge cache', width = 200, onClick = function() end })

  local menu_height = menu.height

  menu:updatePosition(10, 10)
  menu:focusFirstElement()
end

function tools:update(dt)
  menu:update(dt)
end

function tools:draw()
  menu:draw()
  info_window:draw()
end

function tools:keypressed(key)
  menu:keypressed(key)
  if key == "escape" or key == "lalt" then
    scenes:switch("main")
  end
end

return tools
