local scenes            = require("lib.scenes")
local skyscraper        = require("lib.skyscraper")
local pprint            = require("lib.pprint")
local log               = require("lib.log")
local channels          = require("lib.backend.channels")
local configs           = require("helpers.config")
local utils             = require("helpers.utils")
local artwork           = require("helpers.artwork")
local muos              = require("helpers.muos")
local wifi              = require("helpers.wifi")

local component         = require 'lib.gui.badr'
local label             = require 'lib.gui.label'
local popup             = require 'lib.gui.popup'
local listitem          = require 'lib.gui.listitem'
local scroll_container  = require 'lib.gui.scroll_container'
local output_log        = require 'lib.gui.output_log'

local w_width, w_height = love.window.getMode()
local single_scrape     = {}


local menu, info_window, scraping_window, platform_list, rom_list
local user_config = configs.user_config
local theme = configs.theme

local last_selected_platform = nil
local last_selected_rom = nil
local active_column = 1 -- 1 for platforms, 2 for ROMs
local show_missing_only = false
local missing_filter_item = nil

local state = {
  scraping = false,
  fetch_stage = false,
  generate_stage = false,
  current_game = nil,
  current_platform = nil,
  log = {},
}

local function halt_scraping()
  log.write("[single_scrape] Halting scraping operation")
  channels.SKYSCRAPER_ABORT:push({ abort = true })
  
  -- Forcefully kill any running Skyscraper processes immediately
  os.execute("killall -9 Skyscraper Skyscraper.aarch64 2>/dev/null")
  
  -- Give threads a moment to process abort signal
  love.timer.sleep(0.2)
  
  -- Clear all channels to prevent stale data
  channels.SKYSCRAPER_INPUT:clear()
  channels.SKYSCRAPER_GEN_INPUT:clear()
  channels.SKYSCRAPER_GAME_QUEUE:clear()
  channels.SKYSCRAPER_OUTPUT:clear()
  channels.SKYSCRAPER_GEN_OUTPUT:clear()
  while channels.SKYSCRAPER_ABORT:pop() do end -- Clear abort signals
  
  -- Restart threads to ensure clean state
  skyscraper.restart_threads()
  
  state.scraping = false
  state.fetch_stage = false
  state.generate_stage = false
  state.current_game = nil
  state.current_platform = nil
  state.log = {}
  
  if scraping_window then
    scraping_window.visible = false
    -- Clear the log display
    local scraping_log = scraping_window ^ "scraping_log"
    if scraping_log then
      scraping_log.text = ""
    end
  end
  
  log.write("[single_scrape] Scraping halted and state cleared")
end

local function set_rom_list_enabled(enabled)
  if not rom_list or not rom_list.children then return end
  for _, item in ipairs(rom_list.children) do
    item.disabled = not enabled
  end
  if enabled then
    rom_list:focusFirstElement()
  end
end

local function get_required_output_types()
  local p = artwork.get_artwork_path()
  if not p then return { box = true, preview = true, splash = true } end
  local output_types = artwork.get_output_types(p)
  if not output_types then return { box = true, preview = true, splash = true } end
  -- If the template declares no outputs, fall back to requiring boxart
  if not output_types.box and not output_types.preview and not output_types.splash then
    return { box = true, preview = false, splash = false }
  end
  return output_types
end

local function has_missing_media(dest_platform, rom)
  if not dest_platform or not rom then return false end
  local game_title = utils.get_filename(rom)
  if not game_title or game_title == "" then return false end
  local _, catalogue_path = user_config:get_paths()
  if not catalogue_path or catalogue_path == "" then
    return true
  end
  local platform_str = muos.platforms[dest_platform] or dest_platform
  local base = string.format("%s/%s", catalogue_path, platform_str)
  local required = get_required_output_types()

  local function missing_for(output_type)
    local fp = string.format("%s/%s/%s.png", base, output_type, game_title)
    return nativefs.getInfo(fp) == nil
  end

  if required.box and missing_for("box") then return true end
  if required.preview and missing_for("preview") then return true end
  if required.splash and missing_for("splash") then return true end
  return false
end

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
  if missing_filter_item then
    missing_filter_item.disabled = false
  end
  set_rom_list_enabled(true)
end

local function on_rom_press(rom)
  last_selected_rom = rom
  local rom_path, _ = user_config:get_paths()
  local platforms = user_config:get().platforms

  rom_path = string.format("%s/%s", rom_path, last_selected_platform)

  -- Check WiFi connection before scraping
  if not wifi.is_connected() then
    dispatch_info("No WiFi Connection", "Please connect to WiFi and try again.")
    toggle_info()
    return
  end

  local artwork_name = artwork.get_artwork_name()

  if artwork_name then
    local platform_dest = platforms[last_selected_platform]
    -- Prevent running Skyscraper with an unmapped platform
    if not platform_dest or platform_dest == "unmapped" then
      dispatch_info("Error", "Selected platform is not mapped to a muOS core. Open Settings and rescan/assign cores.")
      toggle_info()
    else
      -- Clear any stale abort signals before starting
      while channels.SKYSCRAPER_ABORT:pop() do end
      
      log.write(string.format("[single_scrape] Starting scrape for ROM: %s", rom))
      log.write(string.format("[single_scrape] Platform: %s -> %s", last_selected_platform, platform_dest))
      log.write(string.format("[single_scrape] ROM path: %s", rom_path))
      
      state.scraping = true
      state.fetch_stage = true
      state.generate_stage = false
      state.current_game = utils.get_filename(rom)
      state.current_platform = platform_dest
      state.log = {}
      
      if scraping_window then
        local ui_platform = scraping_window ^ "platform"
        local ui_game = scraping_window ^ "game"
        local ui_status = scraping_window ^ "status"
        if ui_platform then ui_platform.text = muos.platforms[platform_dest] or platform_dest or "N/A" end
        if ui_game then ui_game.text = state.current_game or "N/A" end
        if ui_status then ui_status.text = "Fetching from server..." end
        scraping_window.visible = true
      end
      
      skyscraper.fetch_single(rom_path, rom, last_selected_platform, platform_dest)
    end
  else
    dispatch_info("Error", "Artwork XML not found")
    toggle_info()
  end
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
    if missing_filter_item then
      missing_filter_item.disabled = true
    end
    set_rom_list_enabled(false)
    local active_element = platform_list % last_selected_platform
    platform_list:setFocus(active_element)
  else
    scenes:pop()
  end
end

local function load_rom_buttons(src_platform, dest_platform)
  rom_list.children = {} -- Clear existing ROM items
  rom_list.height = 0

  -- Set label
  (menu ^ "roms_label").text = string.format("%s (%s)", src_platform, dest_platform)

  local rom_path, _ = user_config:get_paths()
  local platform_path = string.format("%s/%s", rom_path, src_platform)
  local roms = nativefs.getDirectoryItems(platform_path)

  -- pprint(dest_platform, artwork.cached_game_ids[dest_platform])

  for _, rom in ipairs(roms) do
    local file_info = nativefs.getInfo(string.format("%s/%s", platform_path, rom))
    if file_info and file_info.type == "file" then
      if show_missing_only and not has_missing_media(dest_platform, rom) then
        goto continue
      end
      -- Green (2) if artwork exists, Red (3) if missing
      local has_artwork = not has_missing_media(dest_platform, rom)
      rom_list = rom_list + listitem {
        text = rom,
        width = ((w_width - 30) / 3) * 2,
        onClick = function()
          on_rom_press(rom)
        end,
        disabled = true,
        active = true,
        indicator = has_artwork and 2 or 3
      }
    end
    ::continue::
  end
end

local function toggle_missing_filter()
  show_missing_only = not show_missing_only
  if missing_filter_item then
    missing_filter_item.text = string.format("Show only missing artwork: %s", show_missing_only and "ON" or "OFF")
    missing_filter_item.icon = show_missing_only and "square_check" or "square"
  end
  if last_selected_platform then
    local rom_path, _ = user_config:get_paths()
    local platforms = user_config:get().platforms
    local dest_platform = platforms and platforms[last_selected_platform]
    if dest_platform and dest_platform ~= "unmapped" then
      load_rom_buttons(last_selected_platform, dest_platform)
      active_column = 2
      set_rom_list_enabled(true)
    end
  end
end

local function load_platform_buttons()
  platform_list.children = {} -- Clear existing platforms
  platform_list.height = 0

  local platforms = user_config:get().platforms

  for src, dest in utils.orderedPairs(platforms or {}) do
    platform_list = platform_list + listitem {
      id = src,
      text = src,
      width = ((w_width - 30) / 3),
      onFocus = function() load_rom_buttons(src, dest) end,
      onClick = function() on_select_platform(src) end,
      disabled = false,
    }
  end
end

local function process_fetched_game()
  local t = channels.SKYSCRAPER_GAME_QUEUE:pop()
  if t then
    if t.skipped then
      state.scraping = false
      state.fetch_stage = false
      scraping_window.visible = false
      dispatch_info("Error", "Unable to generate artwork for selected game [skipped]")
      toggle_info()
      return
    end
    
    state.fetch_stage = false
    state.generate_stage = true
    
    local ui_status = scraping_window ^ "status"
    if ui_status then ui_status.text = "Generating artwork..." end
    
    local rom_path, _ = user_config:get_paths()
    rom_path = string.format("%s/%s", rom_path, last_selected_platform)
    local artwork_name = artwork.get_artwork_name()
    skyscraper.update_artwork(rom_path, last_selected_rom, t.input_folder, t.platform, artwork_name)
  end
end

local function update_scrape_state()
  local t = channels.SKYSCRAPER_OUTPUT:pop()
  if t then
    if t.log then
      table.insert(state.log, t.log)
      if #state.log > 6 then
        table.remove(state.log, 1)
      end
      local log_str = ""
      for _, lstr in ipairs(state.log) do
        log_str = log_str .. lstr .. "\n"
      end
      local scraping_log = scraping_window ^ "scraping_log"
      if scraping_log then
        scraping_log.text = log_str
      end
    end
    
    if t.error and t.error ~= "" then
      state.scraping = false
      state.fetch_stage = false
      state.generate_stage = false
      scraping_window.visible = false
      dispatch_info("Error", t.error)
      toggle_info()
    end
    
    if t.title then
      state.scraping = false
      state.fetch_stage = false
      state.generate_stage = false
      scraping_window.visible = false
      state.log = {}
      
      dispatch_info("Finished", t.success and "Scraping finished successfully" or "Scraping failed or skipped")
      toggle_info()
      
      if t.success then
        artwork.copy_to_catalogue(t.platform, t.title)
        artwork.process_cached_by_platform(t.platform)
        load_rom_buttons(last_selected_platform)
        rom_list:focusFirstElement()
      end
    end
  end
end

function single_scrape:load()
  -- Clear any leftover state from previous scraping sessions
  channels.SKYSCRAPER_ABORT:push({ abort = true })
  channels.SKYSCRAPER_INPUT:clear()
  channels.SKYSCRAPER_GEN_INPUT:clear()
  channels.SKYSCRAPER_GAME_QUEUE:clear()
  channels.SKYSCRAPER_OUTPUT:clear()
  channels.SKYSCRAPER_GEN_OUTPUT:clear()
  while channels.SKYSCRAPER_ABORT:pop() do end
  
  last_selected_platform = nil
  last_selected_rom = nil
  active_column = 1
  show_missing_only = false
  missing_filter_item = nil
  
  state.scraping = false
  state.fetch_stage = false
  state.generate_stage = false
  state.current_game = nil
  state.current_platform = nil
  state.log = {}

  if #artwork.cached_game_ids == 0 then
    artwork.process_cached_data()
  end

  menu = component:root { column = true, gap = 0 }

  info_window = popup { visible = false }
  scraping_window = popup { visible = false, title = "Scraping in progress" }
  platform_list = component { column = true, gap = 0 }
  rom_list = component { column = true, gap = 0 }

  load_platform_buttons()

  local left_column = component { column = true, gap = 10 }
      + label { text = 'Platforms', icon = "folder" }
      + (scroll_container {
          width = (w_width - 30) / 3,
          height = w_height - 90,
          scroll_speed = 30,
        }
        + platform_list)

  local right_column = component { column = true, gap = 10 }
      + label { id = "roms_label", text = 'ROMs', icon = "cd" }
      + (listitem {
        id = "missing_filter",
        text = "Show only missing artwork: OFF",
        icon = "square",
        onClick = toggle_missing_filter,
        disabled = true,
        active = true,
      })
      + (scroll_container {
          width = ((w_width - 30) / 3) * 2,
          height = w_height - 90,
          scroll_speed = 30,
        }
        + rom_list)

  missing_filter_item = right_column % "missing_filter"
  if missing_filter_item then
    missing_filter_item.text = "Show only missing artwork: OFF"
    missing_filter_item.icon = "square"
    missing_filter_item.disabled = true
  end

  menu = menu
      + (component { row = true, gap = 10 }
        + left_column
        + right_column)

  menu:updatePosition(10, 10)
  menu:focusFirstElement()
  
  -- Setup scraping window
  local infoComponent = component { column = true, gap = 10 }
      + label { id = "platform", text = "Platform: N/A", icon = "controller" }
      + label { id = "game", text = "Game: N/A", icon = "cd" }
      + label { id = "status", text = "Status: N/A", icon = "info" }
  
  scraping_window = scraping_window
      + (component { column = true, gap = 15 }
        + infoComponent
        + output_log {
          id = "scraping_log",
          width = scraping_window.width,
          height = 100,
        }
      )
end

function single_scrape:update(dt)
  menu:update(dt)
  update_scrape_state()
  process_fetched_game()
end

function single_scrape:draw()
  love.graphics.clear(theme:read_color("main", "BACKGROUND", "#000000"))
  menu:draw()
  info_window:draw()
  scraping_window:draw()
end

function single_scrape:keypressed(key)
  if key == "escape" then
    if state.scraping then
      halt_scraping()
      return
    end
    on_return()
    return
  end
  
  if not state.scraping then
    menu:keypressed(key)
  end
  
  if key == "lalt" and not state.scraping then
    scenes:push("settings")
  end
end

function single_scrape:gamepadpressed(joystick, button)
  -- Map 'b' button to abort/back action
  if button == "b" then
    if state.scraping then
      halt_scraping()
      return
    end
    on_return()
  end
  
  if not state.scraping then
    if menu.gamepadpressed then
      menu:gamepadpressed(joystick, button)
    end
  end
end

return single_scrape
