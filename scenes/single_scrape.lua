local scenes            = require("lib.scenes")
local skyscraper        = require("lib.skyscraper")
local configs           = require("helpers.config")
local utils             = require("helpers.utils")
local artwork           = require("helpers.artwork")

local component         = require 'lib.gui.badr'
local label             = require 'lib.gui.label'
local popup             = require 'lib.gui.popup'
local listitem          = require 'lib.gui.listitem'
local scroll_container  = require 'lib.gui.scroll_container'

local w_width, w_height = love.window.getMode()
local single_scrape     = {}


local menu, info_window, platform_list, rom_list
local user_config = configs.user_config
local last_selected_platform = nil
local active_column = 1 -- 1 for platforms, 2 for ROMs

local function toggle_info()
  info_window.visible = not info_window.visible
end
local function dispatch_info(title, content)
  info_window.title = title
  info_window.content = content
end

local function on_select_platform(platform)
  last_selected_platform = platform
  active_column = 2
  for _, item in ipairs(platform_list.children) do
    item.disabled = true
    item.active = item.id == platform
  end
  for _, item in ipairs(rom_list.children) do
    item.disabled = false
  end
  rom_list:focusFirstElement()
end

local function on_rom_press(rom)
  local rom_path, _ = user_config:get_paths()
  local platforms = utils.tableMerge(user_config:get().platforms, user_config:get().platformsCustom)

  rom_path = string.format("%s/%s", rom_path, last_selected_platform)

  local artwork_name = artwork.get_artwork_name()

  if artwork_name then
    local platform_dest = platforms[last_selected_platform]
    dispatch_info(rom, "Scraping ROM, please wait...")
    skyscraper.fetch_and_update_artwork(rom_path, rom, platform_dest, artwork_name)
  else
    dispatch_info("Error", "Artwork XML not found")
  end
  toggle_info()
end

local function on_return()
  if info_window.visible then
    toggle_info()
    return
  end
  if active_column == 2 then
    active_column = 1
    for _, item in ipairs(platform_list.children) do
      item.disabled = false
      item.active = false
    end
    for _, item in ipairs(rom_list.children) do
      item.disabled = true
    end
    local active_element = platform_list % last_selected_platform
    platform_list:setFocus(active_element)
  else
    scenes:pop()
  end
end

local function load_rom_buttons(platform)
  rom_list.children = {} -- Clear existing ROM items
  rom_list.height = 0

  -- Set label
  (menu ^ "roms_label").text = platform

  local rom_path, _ = user_config:get_paths()
  local platform_path = string.format("%s/%s", rom_path, platform)
  local roms = nativefs.getDirectoryItems(platform_path)

  for _, rom in ipairs(roms) do
    local file_info = nativefs.getInfo(string.format("%s/%s", platform_path, rom))
    if file_info and file_info.type == "file" then
      rom_list = rom_list + listitem {
        text = rom,
        width = 200,
        onClick = function()
          on_rom_press(rom)
        end,
        disabled = true,
        active = true,
        indicator = artwork.cached_game_ids[rom] and 2 or 3
      }
    end
  end
end

local function load_platform_buttons()
  platform_list.children = {} -- Clear existing platforms
  platform_list.height = 0

  local platforms = utils.tableMerge(user_config:get().platforms, user_config:get().platformsCustom)

  for platform in utils.orderedPairs(platforms or {}) do
    platform_list = platform_list + listitem {
      id = platform,
      text = platform,
      width = 200,
      onFocus = function() load_rom_buttons(platform) end,
      onClick = function() on_select_platform(platform) end,
      disabled = false,
    }
  end
end

local function update_scrape_state()
  local t = OUTPUT_CHANNEL:pop()
  if t then
    if t.error and t.error ~= "" then
      dispatch_info("Error", t.error)
    end
    if t.data and next(t.data) and t.task_id then
      dispatch_info("Finished", t.success and "Scraping finished successfully" or "Scraping failed or skipped")
      artwork.copy_to_catalogue(t.data.platform, t.data.title)
      artwork.process_cached_data()
      load_rom_buttons(last_selected_platform)
      rom_list:focusFirstElement()
    end
  end
end

function single_scrape:load()
  if #artwork.cached_game_ids == 0 then
    artwork.process_cached_data()
  end

  menu = component:root { column = true, gap = 0 }

  info_window = popup { visible = false }
  platform_list = component { column = true, gap = 0 }
  rom_list = component { column = true, gap = 0 }

  load_platform_buttons()

  local left_column = component { column = true, gap = 10 }
      + label { text = 'Platforms', icon = "folder" }
      + (scroll_container {
          width = w_width / 3,
          height = w_height - 90,
          scroll_speed = 30,
        }
        + platform_list)

  local right_column = component { column = true, gap = 10 }
      + label { id = "roms_label", text = 'ROMs', icon = "cd" }
      + (scroll_container {
          width = (w_width / 3) * 2,
          height = w_height - 90,
          scroll_speed = 30,
        }
        + rom_list)

  menu = menu
      + (component { row = true, gap = 10 }
        + left_column
        + right_column)

  menu:updatePosition(10, 10)
  menu:focusFirstElement()
end

function single_scrape:update(dt)
  menu:update(dt)
  update_scrape_state()
end

function single_scrape:draw()
  love.graphics.clear()
  menu:draw()
  info_window:draw()
end

function single_scrape:keypressed(key)
  menu:keypressed(key)
  if key == "escape" then on_return() end
  if key == "lalt" then scenes:push("settings") end
end

return single_scrape
