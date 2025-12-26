local log               = require("lib.log")
local pprint            = require("lib.pprint")
local scenes            = require("lib.scenes")
local skyscraper        = require("lib.skyscraper")
local channels          = require("lib.backend.channels")
local configs           = require("helpers.config")
local artwork           = require("helpers.artwork")
local utils             = require("helpers.utils")

local component         = require 'lib.gui.badr'
local popup             = require 'lib.gui.popup'
local listitem          = require 'lib.gui.listitem'
local scroll_container  = require 'lib.gui.scroll_container'
local output_log        = require 'lib.gui.output_log'
local label             = require 'lib.gui.label'
local icon              = require 'lib.gui.icon'

local tools             = {}
local theme             = configs.theme
local scraper_opts      = { "screenscraper", "thegamesdb" }
local scraper_index     = 1

local region_popup, region_menu, region_list
local selected_region_index = 1
local region_prios = {}
local default_region_prios = { "us", "wor", "eu", "jp", "ss", "uk", "au", "ame", "de", "cus", "cn", "kr", "asi", "br", "sp", "fr", "gr", "it", "no", "dk", "nz", "nl", "pl", "ru", "se", "tw", "ca" }
local region_names = {
  ame = "American continent",
  asi = "Asia",
  au = "Australia",
  br = "Brazil",
  ca = "Canada",
  cn = "China",
  cus = "Custom",
  de = "Germany",
  dk = "Denmark",
  eu = "Europe",
  fr = "France",
  gr = "Greece",
  it = "Italy",
  jp = "Japan",
  kr = "Korea",
  nl = "Netherlands",
  no = "Norway",
  nz = "New Zealand",
  pl = "Poland",
  ru = "Russia",
  se = "Sweden",
  sp = "Spain",
  ss = "ScreenScraper",
  tw = "Taiwan",
  uk = "United Kingdom",
  us = "USA",
  wor = "World",
}

local region_action_ids = { "region_reset", "region_save" }

local function set_region_action_active(id)
  if not region_menu then return end
  for _, aid in ipairs(region_action_ids) do
    local it = region_menu ^ aid
    if it then
      it.active = (aid == id)
    end
  end

  -- Only show one focus indicator at a time. If an action is focused, clear
  -- the region list's active indicator.
  if id and region_list then
    for _, it in ipairs(region_list.children or {}) do
      it.active = false
    end
  end
end

local w_width, w_height = love.window.getMode()

local menu, info_window


local user_config, skyscraper_config = configs.user_config, configs.skyscraper_config
local finished_tasks = 0
local command_output = ""

local function dispatch_info(title, content)
  if title then info_window.title = title end
  if content then
    local scraping_log = info_window ^ "scraping_log"
    scraping_log.text = scraping_log.text .. "\n" .. content
  end
  info_window.visible = true
end

local function update_state()
  local t = channels.SKYSCRAPER_OUTPUT:pop()
  if t then
    -- if t.error and t.error ~= "" then
    --   dispatch_info("Error", t.error)
    -- end
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

local function update_task_state()
  local t = channels.TASK_OUTPUT:pop()
  if t then
    if t.error and t.error ~= "" then
      dispatch_info("Error", t.error)
    end
    if t.output and t.output ~= "" then
      command_output = command_output .. t.output .. "\n"
      local scraping_log = info_window ^ "scraping_log"
      scraping_log.text = command_output
    end
    if t.command_finished then
      if t.command == "backup" then
        dispatch_info("Backed up cache",
          "Cache has been backed up to SD2/ARCHIVE.\nYou can restore it using the muOS Archive Manager")
        log.write("Cache backed up successfully")
      elseif t.command == "migrate" then
        dispatch_info("Migrated cache", "Cache has been migrated to SD2.")
        skyscraper_config:insert("main", "cacheFolder", "\"/mnt/sdcard/scrappy_cache/\"")
        skyscraper_config:save()
        log.write("Cache migrated successfully")
      elseif t.command == "update_app" then
        dispatch_info("Updated Scrappy")
      end
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
  local platforms = user_config:get().platforms
  local rom_path, _ = user_config:get_paths()

  dispatch_info("Updating cache", "Updating cache, please wait...")

  for src, dest in utils.orderedPairs(platforms or {}) do
    if dest ~= "unmapped" then
      local platform_path = string.format("%s/%s", rom_path, src)
      skyscraper.fetch_artwork(platform_path, src, dest)
    end
  end
end

local function on_import_press()
  log.write("Importing custom data")
  dispatch_info("Importing custom data", "Running import command...")
  local import_path = WORK_DIR .. "/static/.skyscraper/import"
  local lookup_folders = {}

  for _, item in ipairs(nativefs.getDirectoryItems(import_path) or {}) do
    local file_info = nativefs.getInfo(string.format("%s/%s", import_path, item))
    if file_info and file_info.type == "directory" then
      table.insert(lookup_folders, item)
    end
  end

  if #lookup_folders == 0 then
    log.write("Import Error: No folders to import")
    dispatch_info("Error", "Error: no folders to import.")
    return
  end

  local platforms = user_config:get().platforms
  local rom_path, _ = user_config:get_paths()

  local any_match = false

  for _, folder in ipairs(lookup_folders) do
    for src, dest in utils.orderedPairs(platforms or {}) do
      if folder == dest then
        any_match = true
        local platform_path = string.format("%s/%s", rom_path, src)
        skyscraper.custom_import(platform_path, dest)
      end
    end
  end

  if not any_match then
    log.write("No matching platforms found")
    dispatch_info("Error", "Error: No matching platforms found.")
    return
  end
end

local function on_change_scraper()
  local index = scraper_index + 1
  if index > #scraper_opts then index = 1 end
  local item = menu ^ "scraper_module"

  skyscraper.module = scraper_opts[index]
  scraper_index = index
  item.text = "Change Skyscraper module (current: " .. scraper_opts[scraper_index] .. ")"
end

local function trim(s)
  return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function parse_region_prios(str)
  local raw = utils.strip_quotes(str or "")
  local list = {}
  for part in tostring(raw):gmatch("[^,]+") do
    local p = trim(part)
    if p ~= "" then
      table.insert(list, p)
    end
  end
  if #list == 0 then
    for _, k in ipairs(default_region_prios) do table.insert(list, k) end
  end
  return list
end

local function rebuild_region_list(focus_index)
  if not region_list then return end
  region_list.children = {}
  region_list.height = 0

  for i, key in ipairs(region_prios) do
    local name = region_names[key] or ""
    local label = name ~= "" and (key .. " - " .. name) or key
    region_list = region_list + listitem {
      id = "region_" .. tostring(i),
      text = string.format("%02d. %s", i, label),
      width = region_list.width,
      onFocus = function()
        selected_region_index = i
        for _, it in ipairs(region_list.children) do
          it.active = (it.id == ("region_" .. tostring(i)))
        end

        -- Only show one focus indicator at a time. If a region is focused,
        -- clear action highlights.
        set_region_action_active(nil)
      end,
      active = (i == selected_region_index),
      indicator = 1,
    }
  end

  local idx = focus_index or selected_region_index
  idx = math.max(1, math.min(#region_list.children, idx))
  selected_region_index = idx
  local focus_item = region_list % ("region_" .. tostring(idx))
  if focus_item and region_menu then
    region_menu:setFocus(focus_item)
  elseif region_menu then
    region_menu:focusFirstElement()
  end
end

local function move_region(delta)
  if #region_prios < 2 then return end
  local i = math.max(1, math.min(#region_prios, selected_region_index))
  local j = i + delta
  if j < 1 or j > #region_prios then return end
  region_prios[i], region_prios[j] = region_prios[j], region_prios[i]
  selected_region_index = j
  rebuild_region_list(selected_region_index)
end

local function reset_region_prios()
  region_prios = {}
  for _, k in ipairs(default_region_prios) do table.insert(region_prios, k) end
  selected_region_index = 1
  rebuild_region_list(1)
end

local function save_region_prios()
  local joined = table.concat(region_prios, ", ")
  skyscraper_config:insert("main", "regionPrios", string.format('"%s"', joined))
  skyscraper_config:save()
  if region_popup then region_popup.visible = false end
end

local function open_region_editor()
  region_prios = parse_region_prios(skyscraper_config:read("main", "regionPrios"))
  selected_region_index = 1

  region_menu = component:root { column = true, gap = 10 }
  local item_width = math.min(w_width - 120, 560)
  local list_height = math.min(w_height - 220, 360)

  region_list = component { id = "region_list", column = true, gap = 0, width = item_width, height = 0 }
  rebuild_region_list(1)

  region_menu = region_menu
      + (component { row = true, gap = 6 }
        + icon { name = "info", size = 20, y = 6 }
        + label {
          text = "Up/Down: select • Left/Right: reorder •",
          y = 6,
        }
        + icon { name = "button_a", size = 24, y = 8 }
        + label { text = "Confirm", y = 6 }
      )
      + (scroll_container { width = item_width, height = list_height, scroll_speed = 30 } + region_list)
      + listitem {
        id = "region_reset",
        text = "Reset to default",
        width = item_width,
        onClick = reset_region_prios,
        onFocus = function() set_region_action_active("region_reset") end,
        icon = "refresh",
      }
      + listitem {
        id = "region_save",
        text = "Save",
        width = item_width,
        onClick = save_region_prios,
        onFocus = function() set_region_action_active("region_save") end,
      }

  region_menu:updatePosition(0, 0)
  region_menu:focusFirstElement()

  region_popup = popup { visible = true, title = "Region Priorities", id = "region_popup" }
  region_popup.children = { region_menu }
end

local function on_reset_configs()
  user_config:start_fresh()
  skyscraper_config:start_fresh()
  dispatch_info("Configs reset", "Configs have been reset.")
end

local function on_backup_cache()
  log.write("Backing up cache to ARCHIVE folder")
  dispatch_info("Backing up cache to SD2/ARCHIVE folder", "Please wait...")
  local thread = love.thread.newThread("lib/backend/task_backend.lua")
  thread:start("backup")
end

local function on_migrate_cache()
  log.write("Migrating cache to SD2")
  dispatch_info("Migrating cache to SD2", "Please wait...")
  local thread = love.thread.newThread("lib/backend/task_backend.lua")
  thread:start("migrate")
end

local function on_app_update()
  log.write("Updating Scrappy")
  dispatch_info("Updating Scrappy", "Please wait...")
  local thread = love.thread.newThread("lib/backend/task_backend.lua")
  thread:start("update_app")
end

function tools:load()
  menu = component:root { column = true, gap = 10 }
  info_window = popup { visible = false }
  local item_width = w_width - 20

  menu = menu
      + (scroll_container {
          width = w_width,
          height = w_height - 60,
          scroll_speed = 30,
        }
        + (component { column = true, gap = 10 }
          -- TODO: Implement auto update
          + listitem {
            text = "Update Scrappy",
            width = item_width,
            onClick = on_app_update,
            icon = "download"
          }
          + listitem {
            text = "Migrate cache to SD2",
            width = item_width,
            onClick = on_migrate_cache,
            icon = "sd_card"
          }
          + listitem {
            text = "Backup cache to SD2/ARCHIVE folder",
            width = item_width,
            onClick = on_backup_cache,
            icon = "sd_card"
          }
          + listitem {
            id = "scraper_module",
            text = "Change Skyscraper module (current: " .. scraper_opts[scraper_index] .. ")",
            width = item_width,
            onClick = on_change_scraper,
            icon = "canvas"
          }
          + listitem {
            text = "Edit region priorities",
            width = item_width,
            onClick = open_region_editor,
            icon = "info"
          }
          + listitem {
            text = "Update cache (uses threads, doesn't generate artwork)",
            width = item_width,
            onClick = on_update_press,
            icon = "sd_card"
          }
          + listitem {
            text = "Run custom import (adds custom data to cache, read Wiki!)",
            width = item_width,
            onClick = on_import_press,
            icon = "file_import"
          }
          + listitem {
            text = "Rescan ROMs folders (overwrites [platforms] config)",
            width = item_width,
            onClick = on_refresh_press,
            icon = "folder"
          }
          + listitem {
            text = "Reset configs (can't be undone!)",
            width = item_width,
            onClick = on_reset_configs,
            icon = "refresh"
          }
        )
      )

  info_window = info_window
      + (
        component { column = true, gap = 15 }
        + output_log {
          visible = false,
          id = "scraping_log",
          width = info_window.width,
          height = w_height * 0.50,
        }
      )

  menu:updatePosition(10, 10)
  menu:focusFirstElement()
end

function tools:update(dt)
  if region_popup and region_popup.visible and region_menu then
    region_menu:update(dt)
  else
    menu:update(dt)
  end
  update_state()
  update_task_state()
end

function tools:draw()
  love.graphics.clear(theme:read_color("main", "BACKGROUND", "#000000"))
  menu:draw()
  info_window:draw()
  if region_popup and region_popup.visible then
    region_popup:draw()
  end
end

function tools:keypressed(key)
  if region_popup and region_popup.visible then
    if key == "escape" then
      region_popup.visible = false
      return
    end
    if region_menu and (key == "left" or key == "right") then
      local focused = region_menu:getRoot().focusedElement
      if focused and type(focused.id) == "string" and focused.id:match("^region_%d+$") then
        move_region(key == "left" and -1 or 1)
        return
      end
    end
    if region_menu then region_menu:keypressed(key) end
    return
  end

  menu:keypressed(key)
  if key == "escape" then
    if info_window.visible then
      info_window.visible = false
      command_output = ""
      local scraping_log = info_window ^ "scraping_log"
      scraping_log.text = ""
    else
      scenes:pop()
    end
  end
end

return tools
