local log           = require("lib.log")
local scenes        = require("lib.scenes")
local skyscraper    = require("lib.skyscraper")
local configs       = require("helpers.config")
local artwork       = require("helpers.artwork")
local utils         = require("helpers.utils")

local component     = require 'lib.gui.badr'
local button        = require 'lib.gui.button'
local label         = require 'lib.gui.label'
local popup         = require 'lib.gui.popup'
local select        = require 'lib.gui.select'

local tools         = {}
local theme         = configs.theme
local scraper_opts  = { "screenscraper", "thegamesdb" }
local scraper_index = 1

local menu, info_window


local user_config, skyscraper_config = configs.user_config, configs.skyscraper_config
local finished_tasks = 0

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
      finished_tasks = finished_tasks + 1
      dispatch_info(nil, string.format("Finished %d games", finished_tasks))
    end
    if t.command_finished then
      dispatch_info("Updated cache", "Cache has been updated.")
      finished_tasks = 0
      log.write("Cache updated successfully")
      artwork.process_cached_data()
    end
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

  dispatch_info("Updating cache, please wait...", string.format("Finished %d games", finished_tasks))

  for src, dest in utils.orderedPairs(platforms or {}) do
    if dest ~= "unmapped" then
      local platform_path = string.format("%s/%s", rom_path, src)
      skyscraper.fetch_artwork(platform_path, dest, "update")
    end
  end
end

local function on_import_press()
  log.write("Importing custom data")
  local import_path = WORK_DIR .. "/static/.skyscraper/import"
  local lookup_folders = {}

  for _, item in ipairs(nativefs.getDirectoryItems(import_path) or {}) do
    local file_info = nativefs.getInfo(string.format("%s/%s", import_path, item))
    if file_info and file_info.type == "directory" then
      print(item)
      table.insert(lookup_folders, item)
    end
  end

  if #lookup_folders == 0 then
    log.write("No folders to import")
    dispatch_info("Error", "No folders to import.")
    return
  end

  local platforms = utils.tableMerge(user_config:get().platforms, user_config:get().platformsCustom)
  local rom_path, _ = user_config:get_paths()

  for _, folder in ipairs(lookup_folders) do
    for src, dest in utils.orderedPairs(platforms or {}) do
      if folder == dest then
        print("FOUND MATCH", folder, dest)
        local platform_path = string.format("%s/%s", rom_path, src)
        skyscraper.custom_import(platform_path, dest)
      end
    end
  end
end

local function on_change_scraper(index)
  skyscraper.module = scraper_opts[index]
  scraper_index = index
end

local function on_reset_configs()
  user_config:start_fresh()
  skyscraper_config:start_fresh()
  dispatch_info("Configs reset", "Configs have been reset.")
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
        + button { text = 'Run custom import', width = 200, onClick = on_import_press })
      + (component { column = true, gap = 0 }
        + label { text = 'Temporarily changes Skyscraper module. Useful for ROM hacks.', icon = "download" }
        + select {
          width = 200,
          options = scraper_opts,
          startIndex = scraper_index,
          onChange = function(_, index) on_change_scraper(index) end
        })
      + (component { column = true, gap = 0 }
        + label { text = 'Resets user and Skyscraper configs. Can\'t be undone.', icon = "refresh" }
        + button { text = 'Reset configs', width = 200, onClick = on_reset_configs })

  menu:updatePosition(10, 10)
  menu:focusFirstElement()
end

function tools:update(dt)
  menu:update(dt)
  update_state()
end

function tools:draw()
  love.graphics.clear(theme:read_color("main", "BACKGROUND", "#000000"))
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
