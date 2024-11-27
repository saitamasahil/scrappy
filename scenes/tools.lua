local log               = require("lib.log")
local scenes            = require("lib.scenes")
local skyscraper        = require("lib.skyscraper")
local configs           = require("helpers.config")
local utils             = require("helpers.utils")

local component         = require 'lib.gui.badr'
local button            = require 'lib.gui.button'
local label             = require 'lib.gui.label'
local popup             = require 'lib.gui.popup'

local user_config       = configs.user_config
local w_width, w_height = love.window.getMode()

local tools             = {}

local menu, info_window


local finished_cache_tasks = 0

local function dispatch_info(title, content)
  if title then info_window.title = title end
  if content then info_window.content = content end
  info_window.visible = true
end

local function update_state()
  local t = OUTPUT_CHANNEL:pop()
  if t then
    if t.error and t.error ~= "" then
      dispatch_info("Error", t.error)
    end
    if t.data and next(t.data) then
      dispatch_info(string.format("Updating cache for %s, please wait...", t.data.platform))
    end
    if t.success ~= nil then
      finished_cache_tasks = finished_cache_tasks + 1
      dispatch_info(nil, string.format("Finished %d games", finished_cache_tasks))
    end
  end
  if finished_cache_tasks > 0 and INPUT_CHANNEL:getCount() == 0 then
    dispatch_info("Updated cache", "Cache has been updated.")
    finished_cache_tasks = 0
    log.write("Cache updated successfully")
  end
end

local function on_refresh_press()
  user_config:load_platforms()
  user_config:save()
  dispatch_info("Refreshed platforms", "Platforms have been refreshed.")
end

local function on_update_press()
  log.write("Updating cache")
  local platforms = utils.tableMerge(user_config:get().platforms, user_config:get().platformsCustom)
  local rom_path, _ = user_config:get_paths()

  dispatch_info("Updating cache, please wait...", string.format("Finished %d games", finished_cache_tasks))

  for src, dest in utils.orderedPairs(platforms or {}) do
    if dest ~= "unmapped" then
      local platform_path = string.format("%s/%s", rom_path, src)
      skyscraper.fetch_artwork(platform_path, dest, "update")
    end
  end
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
        + button { text = 'Update cache', width = 200, onClick = on_update_press })
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
  update_state()
end

function tools:draw()
  love.graphics.clear()
  menu:draw()
  info_window:draw()
end

function tools:keypressed(key)
  menu:keypressed(key)
  if key == "escape" then
    if info_window.visible then
      info_window.visible = false
    else
      scenes:pop()
    end
  end
end

return tools
