local scenes            = require("lib.scenes")
local configs           = require("helpers.config")
local utils             = require("helpers.utils")

local component         = require 'lib.gui.badr'
local button            = require 'lib.gui.button'
local label             = require 'lib.gui.label'
local checkbox          = require 'lib.gui.checkbox'
local select            = require 'lib.gui.select'
local scroll_container  = require 'lib.gui.scroll_container'
local popup             = require 'lib.gui.popup'
local output_log        = require 'lib.gui.output_log'

local virtual_keyboard = require 'lib.gui.virtual_keyboard'


local user_config       = configs.user_config
local theme             = configs.theme
local w_width, w_height = love.window.getMode()
-- Smaller font for virtual keyboard labels
local vk_font = love.graphics.newFont(_G.MAIN_FONT_PATH or 12, 12)
-- Larger font for password preview (bigger asterisks)
local vk_password_font = love.graphics.newFont(_G.MAIN_FONT_PATH or 18, 18)

local settings          = {}

local menu, content, scroller, checkboxes
local info_window

local all_check         = true

-- Screenscraper account state
local ss_username = ""
local ss_password = ""
local ss_show_password = false
local igdb_client_id = ""
local igdb_client_secret = ""

-- TheGamesDB API Key Server State
local tgdb_server_running = false
local tgdb_server_ip = nil
local tgdb_check_timer = 0
local tgdb_key_exists = false
local TMP_TGDB_KEY_FILE = "/tmp/scrappy_tgdb_key.txt"
local IGDB_CRED_FILE_PATHS = {
  WORK_DIR .. "/igdb_credentials.txt",
  WORK_DIR .. "/static/igdb_credentials.txt",
  "/tmp/scrappy_igdb_credentials.txt"
}

local MASK_CHAR = "*"
local function load_screenscraper_creds()
  local sk = configs.skyscraper_config
  local creds = sk:read("screenscraper", "userCreds") or ""
  if creds and creds ~= "" then
    -- Remove surrounding quotes if present and trim
    local cleaned = creds:gsub('^%s*"', ""):gsub('"%s*$', "")
    local u, p = cleaned:match('([^:]+):(.+)')
    if u and p then
      ss_username = u
      ss_password = p
    end
  end
end

local function load_igdb_creds()
  local sk = configs.skyscraper_config
  local creds = sk:read("igdb", "userCreds") or ""
  if creds and creds ~= "" then
    -- Remove surrounding quotes if present and trim
    local cleaned = creds:gsub('^%s*"', ""):gsub('"%s*$', "")
    local client_id, client_secret = cleaned:match('([^:]+):(.+)')
    if client_id and client_secret then
      igdb_client_id = client_id
      igdb_client_secret = client_secret
    end
  end
end

local function masked(text)
  return text ~= nil and text ~= "" and string.rep(MASK_CHAR, #text) or "(set)"
end

local function on_vk_done(buffer, target)
  if target == 'user' then ss_username = buffer end
  if target == 'pass' then ss_password = buffer end
  if target == 'igdb_client_id' then igdb_client_id = buffer end
  if target == 'igdb_client_secret' then igdb_client_secret = buffer end
end

local function on_vk_cancel(target)
  -- just hide, no changes
end

local function vk_show(target, initial)
  local current = initial or (target == 'user' and ss_username or ss_password) or ""
  if target == 'user' and current == "USER" then current = "" end
  if target == 'pass' and current == "PASS" then current = "" end
  
  vk:show(current, target)
  if target == 'pass' then
    vk.mask_input = not ss_show_password
  elseif target == 'igdb_client_secret' then
    vk.mask_input = true
  else
    vk.mask_input = false
  end
end



local function on_filter_resolution(index)
  local filtering = user_config:read("main", "filterTemplates") == "1"
  user_config:insert("main", "filterTemplates", filtering and "0" or "1")
  user_config:save()
end

local function on_concurrent_change(_, idx)
  -- idx is 1-based (1-8), save it directly
  user_config:insert("main", "concurrentGeneration", tostring(idx))
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
  local selected_platforms = user_config:get().platformsSelected
  for platform in utils.orderedPairs(platforms or {}) do
    checkboxes = checkboxes + checkbox {
      text = platform,
      id = platform,
      onToggle = function() on_change_platform(platform) end,
      checked = selected_platforms[platform] == "1",
      width = w_width - 20,
    }
  end
end

local function dispatch_info(title, content_text)
  if not info_window then return end
  info_window.title = title
  local log_comp = info_window ^ "scraping_log"
  if log_comp then
    log_comp.text = content_text
  end
  info_window.visible = true
  info_window.fade = 0 -- Reset fade for zoom animation
end

local function on_refresh_press()
  local btn = menu ^ "rescan_btn"
  if btn then btn.text = "Scanning..." end
  -- Force a slight delay or draw to let UI update? (Not easily possible in blocking sync)
  
  user_config:load_platforms()
  user_config:save()
  update_checkboxes()
  if content and content.recalculateSize then
    content:recalculateSize()
  end
  
  if btn then btn.text = "Rescan folders" end
  
  dispatch_info("Scan Complete", "Folder scan finished. Platform list updated.\nIf you see unticked folders, make sure you have assigned cores in muOS (Folders/Subfolders).")
end

local on_check_all_press = function()
  local selected_platforms = user_config:get().platformsSelected
  for platform, _ in pairs(selected_platforms) do
    user_config:insert("platformsSelected", platform, all_check and "0" or "1")
  end
  all_check = not all_check
  user_config:save()
  update_checkboxes()
end

-- Screenscraper helpers
local function on_edit_username()
  -- Do not reload creds here; use the live in-memory value to avoid resetting unsaved input
  vk_show('user', ss_username)
end

local function on_edit_password()
  -- Do not reload creds here; use the live in-memory value to avoid resetting unsaved input
  vk_show('pass', ss_password)
end

local function on_save_ss()
  local sk = configs.skyscraper_config
  if ss_username ~= '' and ss_password ~= '' then
    sk:insert('screenscraper', 'userCreds', string.format('"%s:%s"', ss_username, ss_password))
    sk:save()
    sk:sync_native_config()
    dispatch_info("ScreenScraper", "Saved credentials.")
  else
    dispatch_info("ScreenScraper", "Enter both username and password.")
  end
end

local function on_toggle_show_password()
  ss_show_password = not ss_show_password
end

local function trim(s)
  return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function parse_igdb_credentials(raw)
  if not raw or raw == "" then
    return nil, nil
  end

  local client_id = nil
  local client_secret = nil
  local fallback_line = nil

  for line in tostring(raw):gmatch("[^\r\n]+") do
    local cleaned = trim(line)
    if cleaned ~= "" and cleaned:sub(1, 1) ~= "#" then
      local key, value = cleaned:match("^([%w_%-]+)%s*=%s*(.+)$")
      if key and value then
        local k = trim(key):lower()
        local v = trim(value):gsub('^"(.*)"$', "%1")
        if k == "client_id" or k == "clientid" or k == "client-id" then
          client_id = v
        elseif k == "client_secret" or k == "clientsecret" or k == "client-secret" then
          client_secret = v
        end
      elseif not fallback_line then
        fallback_line = cleaned
      end
    end
  end

  if client_id and client_secret then
    return client_id, client_secret
  end

  if fallback_line then
    local id, secret = fallback_line:match("^([^:]+):(.+)$")
    if id and secret then
      return trim(id), trim(secret)
    end
  end

  return nil, nil
end

local function on_edit_igdb_client_id()
  vk_show('igdb_client_id', igdb_client_id)
end

local function on_edit_igdb_client_secret()
  vk_show('igdb_client_secret', igdb_client_secret)
end

local function on_save_igdb()
  local sk = configs.skyscraper_config
  if igdb_client_id ~= '' and igdb_client_secret ~= '' then
    sk:insert('igdb', 'userCreds', string.format('"%s:%s"', igdb_client_id, igdb_client_secret))
    sk:save()
    sk:sync_native_config()
    dispatch_info("IGDB", "Saved client credentials.")
  else
    dispatch_info("IGDB", "Enter both Client ID and Client Secret.")
  end
end

local function on_load_igdb_from_file()
  local found_path = nil
  local contents = nil

  for _, path in ipairs(IGDB_CRED_FILE_PATHS) do
    local f = io.open(path, "r")
    if f then
      contents = f:read("*a")
      f:close()
      found_path = path
      break
    end
  end

  if not found_path then
    dispatch_info("IGDB", "No credentials file found.\nCreate one of:\n" ..
      IGDB_CRED_FILE_PATHS[1] .. "\n" .. IGDB_CRED_FILE_PATHS[2] .. "\n" .. IGDB_CRED_FILE_PATHS[3] ..
      "\n\nFormat:\nclient_id=...\nclient_secret=...\n(or CLIENT_ID:CLIENT_SECRET)")
    return
  end

  local client_id, client_secret = parse_igdb_credentials(contents)
  if not client_id or not client_secret or client_id == "" or client_secret == "" then
    dispatch_info("IGDB", "Invalid IGDB credentials file format at:\n" .. found_path ..
      "\n\nUse either:\nclient_id=...\nclient_secret=...\n\nor\nCLIENT_ID:CLIENT_SECRET")
    return
  end

  igdb_client_id = client_id
  igdb_client_secret = client_secret

  local sk = configs.skyscraper_config
  sk:insert('igdb', 'userCreds', string.format('"%s:%s"', igdb_client_id, igdb_client_secret))
  sk:save()
  sk:sync_native_config()

  dispatch_info("IGDB", "Loaded IGDB credentials from:\n" .. found_path)
end

local function on_enter_tgdb_key_web()
  if tgdb_server_running then
    -- Cancel server
    os.execute("pkill -f tgdb_server.py")
    tgdb_server_running = false
    dispatch_info("TheGamesDB Web Server", "Server stopped.")
    return
  end

  local ip = utils.get_ip_address()
  if ip then
    -- Make sure temp file is clear
    love.filesystem.remove(TMP_TGDB_KEY_FILE)
    os.execute("rm -f " .. TMP_TGDB_KEY_FILE)
    
    -- Start python server in background
    -- Use WORK_DIR to ensure it works correctly regardless of SD1/SD2 install location
    local server_path = WORK_DIR .. "/scripts/tgdb_server.py"
    local logo_path = WORK_DIR .. "/assets/scrappy_logo.png"
    local theme_name = theme:get_current_name() or "dark"
    -- Get the accent color (hex string without #)
    local accent_color = configs.user_config:read("main", "customAccent") or "cbaa0f"
    local accent_mode = tostring(configs.user_config:read("main", "accentMode") or "muos"):lower()
    if accent_mode == "muos" then
      -- Use muOS accent from the theme's BUTTON_FOCUS
      accent_color = theme:read("button", "BUTTON_FOCUS") or "cbaa0f"
    end
    os.execute(string.format('python3 "%s" --theme %s --accent "%s" --logo "%s" > /dev/null 2>&1 &',
      server_path, theme_name, accent_color, logo_path))
    
    tgdb_server_running = true
    tgdb_server_ip = ip
    dispatch_info("TheGamesDB Web Server", 'Go to http://' .. ip .. ':8080 on phone/PC (same WiFi)\n\nWaiting for you to enter the API key...')
    tgdb_check_timer = 0
  else
    dispatch_info("TheGamesDB Web Server", "No IP found! Connect to WiFi.")
  end
end

function settings:load()
  load_screenscraper_creds()
  load_igdb_creds()
  
  vk = virtual_keyboard.create({
    on_done = on_vk_done,
    on_cancel = on_vk_cancel,
    placeholder = "Enter text..."
  })

  local tgdb_creds = configs.skyscraper_config:read("thegamesdb", "userCreds")
  tgdb_key_exists = (tgdb_creds ~= nil and tgdb_creds ~= "" and tgdb_creds ~= '""')

  -- Root container holds just the scroller; content lives inside scroller
  menu = component:root { column = true, gap = 10 }
  content = component { column = true, gap = 10 }
  checkboxes = component { column = true, gap = 0 }

  -- Build the non-platform sections into content
  content = content
      + label { text = 'ScreenScraper Account', icon = "user" }
      + (component { column = true, gap = 6 }
          + button { text = function() return 'Username: ' .. (ss_username ~= '' and ss_username or '(set)') end, width = w_width - 20, onClick = on_edit_username }
          + button { text = function()
                local pw = ss_show_password and (ss_password == '' and '(set)' or ss_password) or masked(ss_password)
                return 'Password: ' .. pw
              end, width = w_width - 20, onClick = on_edit_password }
        )
      + (component { row = true, gap = 10 }
          + button { text = 'Save', width = 160, onClick = on_save_ss }
          + button { text = function() return ss_show_password and 'Hide Password' or 'Show Password' end, width = 180, onClick = on_toggle_show_password }
        )

      + label { text = 'IGDB Account', icon = "user" }
      + (component { column = true, gap = 6 }
          + button {
              text = function() return 'Client ID: ' .. (igdb_client_id ~= '' and igdb_client_id or '(set)') end,
              width = w_width - 20,
              onClick = on_edit_igdb_client_id
            }
          + button {
              text = function() return 'Client Secret: ' .. masked(igdb_client_secret) end,
              width = w_width - 20,
              onClick = on_edit_igdb_client_secret
            }
        )
      + (component { row = true, gap = 10 }
          + button { text = 'Save IGDB', width = 180, onClick = on_save_igdb }
        )
      + button {
          text = 'Load IGDB from text file',
          width = w_width - 20,
          onClick = on_load_igdb_from_file
        }
      
      + label { text = 'TheGamesDB Account', icon = "user" }
      + (component { column = true, gap = 6 }
          + button { 
              text = function() 
                if tgdb_server_running then
                  return 'Stop Server (IP: ' .. (tgdb_server_ip or "") .. ')'
                elseif tgdb_key_exists then
                  return 'Update API Key via Web Server (Key Saved)'
                else
                  return 'Enter API Key via Web Server'
                end
              end, 
              width = w_width - 20, 
              onClick = on_enter_tgdb_key_web 
            }
        )
      
      + label { text = 'Resolution', icon = "display" }
      + checkbox {
        text = 'Filter templates for my resolution (Restart required)',
        onToggle = on_filter_resolution,
        checked = user_config:read("main", "filterTemplates") == "1"
      }
      + label { text = 'Performance', icon = "performance" }
      + label { text = 'Concurrent artwork generation (1-8) (Restart required):' }
      + select {
        width = w_width - 20,
        options = {"1", "2", "3", "4", "5", "6", "7", "8"},
        startIndex = tonumber(user_config:read("main", "concurrentGeneration") or "3"),
        onChange = on_concurrent_change
      }
      + label { text = 'Platforms', icon = "folder" }
      + (component { row = true, gap = 10 }
        + button { id = 'rescan_btn', text = 'Rescan folders', width = 200, onClick = on_refresh_press }
        + button { text = 'Un/check all', width = 200, onClick = on_check_all_press })

  -- Populate platforms list
  update_checkboxes()

  if not user_config:has_platforms() then
    content = content + label {
      text = "No platforms found; your paths might not have cores assigned",
      icon = "warn",
    }
  else
    content = content + checkboxes
  end

  -- Wrap entire content in a single scroll container so the whole UI scrolls
  scroller = scroll_container {
    width = w_width - 20,
    -- Subtract footer/help area so the bar isn't covered by the scroller
    height = w_height - 50,
    scroll_speed = 30,
  } + content

  menu = menu + scroller

  -- Position and focus
  menu:updatePosition(10, 10)
  menu:focusFirstElement()

  info_window = popup {
    title = "Information",
    width = w_width * 0.8,
    height = w_height * 0.5,
    visible = false
  }
  info_window = info_window + (component {
    column = true,
    gap = 15
  } + output_log {
    id = "scraping_log",
    width = info_window.width - 20,
    height = info_window.height * 0.8
  })
end

function settings:update(dt)
  if vk and vk.visible then
    vk:update(dt)
    return -- Skip all background updates while keyboard is active
  end

  if info_window and info_window.visible then
    info_window:update(dt)
  else
    menu:update(dt)
  end
  
  if tgdb_server_running then
    tgdb_check_timer = tgdb_check_timer + dt
    if tgdb_check_timer >= 1.0 then
      tgdb_check_timer = 0
      local f = io.open(TMP_TGDB_KEY_FILE, "r")
      if f then
        local key = f:read("*a")
        f:close()
        if key and key ~= "" then
          local sk = configs.skyscraper_config
          sk:insert('thegamesdb', 'userCreds', '"' .. key:gsub("%s+", "") .. '"')
          sk:save()
          sk:sync_native_config()
          tgdb_key_exists = true
          tgdb_server_running = false
          dispatch_info("TheGamesDB Web Server", "API Key saved successfully!")
          os.remove(TMP_TGDB_KEY_FILE)
        end
      end
    end
  end
end

function settings:draw()
  love.graphics.clear(theme:read_color("main", "BACKGROUND", "#000000"))
  menu:draw()
  if info_window and info_window.visible then
    info_window:draw()
  end
  if vk and vk.visible then
    vk:draw()
  end
end

function settings:keypressed(key)
  if vk and vk.visible then
    local map = {
      up = 'up', down = 'down', left = 'left', right = 'right',
      ["return"] = 'confirm', escape = 'cancel', backspace = 'backspace',
      x = 'x', y = 'y', space = 'space'
    }
    if map[key] then
      vk:handle_key(map[key])
      return
    end
    return
  end

  if info_window and info_window.visible then
    if key == "escape" or key == "b" or key == "return" then
      info_window.visible = false
    end
    return
  end

  menu:keypressed(key)
  if key == "escape" or key == "lalt" then
    scenes:pop()
  end
end

function settings:gamepadpressed(joystick, button)
  if vk and vk.visible then
    local map = {
      dpup = 'up', dpdown = 'down', dpleft = 'left', dpright = 'right',
      a = 'confirm', b = 'cancel', x = 'x', y = 'y'
    }
    local btn = type(button) == 'string' and button:lower() or button
    if map[btn] then
      vk:handle_key(map[btn])
      return true
    end
    return true
  end
  
  if info_window and info_window.visible then
    if button == "b" or button == "a" or button == "start" then
      info_window.visible = false
    end
    return true
  end

  if menu.gamepadpressed then return menu:gamepadpressed(joystick, button) end
  return false
end

return settings
