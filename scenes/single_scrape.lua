local scenes            = require("lib.scenes")
local pprint            = require("lib.pprint")
local configs           = require("helpers.config")
local utils             = require("helpers.utils")

local component         = require 'lib.gui.badr'
local button            = require 'lib.gui.button'
local label             = require 'lib.gui.label'
local popup             = require 'lib.gui.popup'
local listitem          = require 'lib.gui.listitem'
local select            = require 'lib.gui.select'
local checkbox          = require 'lib.gui.checkbox'
local scroll_container  = require 'lib.gui.scroll_container'

local user_config       = configs.user_config
local w_width, w_height = love.window.getMode()

local single_scrape     = {}

local menu, info_window, platform_list, rom_list


local function toggle_info()
  info_window.visible = not info_window.visible
end
local function dispatch_info(title, content)
  info_window.title = title
  info_window.content = content
end

local function load_rom_buttons(platform)
  local rom_path, _ = user_config:get_paths()
  local platform_path = string.format("%s/%s", rom_path, platform)
  local roms = nativefs.getDirectoryItems(platform_path)

  rom_list.children = {}
  for _, rom in ipairs(roms) do
    local file_info = nativefs.getInfo(string.format("%s/%s", platform_path, rom))
    if file_info and file_info.type == "file" then
      rom_list = rom_list + listitem {
        text = rom,
        width = 200,
        onFocus = function() print("focused " .. rom) end,
        disabled = true,
      }
    end
  end
end

local function load_platform_buttons()
  platform_list.children = {}
  local platforms = user_config:get().platforms
  local custom_platforms = user_config:get().platformsCustom
  for platform in utils.orderedPairs(platforms or {}) do
    platform_list = platform_list + listitem {
      id = platform,
      text = platform,
      width = 200,
      onFocus = function() load_rom_buttons(platform) end,
    }
  end
  pprint(platform_list.children)
  -- for custom in utils.orderedPairs(custom_platforms or {}) do
  --   platform_list = platform_list + listitem {
  --     text = custom,
  --     width = 200,
  --     onFocus = function() print("focused " .. custom) end,
  --   }
  -- end
end

function single_scrape:load()
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
      + label { text = 'ROMs', icon = "cd" }
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


  local menu_height = menu.height

  menu:updatePosition(10, 10)
  menu:focusFirstElement()
end

function single_scrape:update(dt)
  menu:update(dt)
end

function single_scrape:draw()
  menu:draw()
  info_window:draw()
end

function single_scrape:keypressed(key)
  menu:keypressed(key)
  if key == "escape" or key == "lalt" then
    scenes:switch("main")
  end
end

return single_scrape
