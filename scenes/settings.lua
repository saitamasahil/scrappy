local scenes            = require("lib.scenes")
local configs           = require("helpers.config")
local utils             = require("helpers.utils")

local component         = require 'lib.gui.badr'
local button            = require 'lib.gui.button'
local label             = require 'lib.gui.label'
local checkbox          = require 'lib.gui.checkbox'
local scroll_container  = require 'lib.gui.scroll_container'

-- Virtual keyboard layout for gamepad input
local VKEY = {
  {'1','2','3','4','5','6','7','8','9','0'},
  {'q','w','e','r','t','y','u','i','o','p'},
  {'a','s','d','f','g','h','j','k','l'},
  {'z','x','c','v','b','n','m',' '},
  {'SHIFT','DEL','SPACE','DONE'}
}

local VKEY_SHIFT = {
  {'!','@','#','$','%','^','&','*','(',')'},
  {'Q','W','E','R','T','Y','U','I','O','P'},
  {'A','S','D','F','G','H','J','K','L'},
  {'Z','X','C','V','B','N','M',' '},
  {'shift','DEL','SPACE','DONE'}
}

local user_config       = configs.user_config
local theme             = configs.theme
local w_width, w_height = love.window.getMode()
-- Smaller font for virtual keyboard labels
local vk_font = love.graphics.newFont(12)

local settings          = {}

local menu, content, scroller, checkboxes

local all_check         = true

-- Screenscraper account state
local ss_username = ""
local ss_password = ""
local ss_show_password = false
local ss_status = ""
local vk = nil  -- virtual keyboard instance
local vk_visible = false
local vk_shift = false
local vk_row, vk_col = 1, 1
local vk_buffer = ""
local vk_target = nil -- 'user' | 'pass'
local vk_hold_dir = nil
local vk_hold_time = 0
local vk_repeat_delay = 0.28
local vk_repeat_rate = 0.06
local vk_repeat_started = false
local vk_hold_acc = 0
local vk_char_font = nil
local vk_char_font_size = 0
local vk_mode = 'lower' -- lower | upper | symbol
local vk_last_char_time = 0
local vk_last_char_window = 0.8

-- Optional pixel icon support for special keys (if PNGs exist)
-- Expected files under assets/icons/: key_shift.png, key_backspace.png, key_space.png, key_enter.png
local VK_ICONS = {
  shift = { path = "assets/icons/key_shift.png", img = nil },
  del   = { path = "assets/icons/key_backspace.png", img = nil },
  space = { path = "assets/icons/key_space.png", img = nil },
  done  = { path = "assets/icons/key_enter.png", img = nil },
}

local function load_vk_icon(kind)
  local entry = VK_ICONS[kind]
  if not entry then return nil end
  if entry.img ~= nil then return entry.img end
  if love.filesystem.getInfo(entry.path) then
    local ok, img = pcall(love.graphics.newImage, entry.path)
    if ok and img then
      entry.img = img
      return img
    end
  end
  entry.img = false -- mark as not available
  return nil
end

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

local MASK_CHAR = "*"
local function masked(text)
  return text ~= nil and text ~= "" and string.rep(MASK_CHAR, #text) or "(set)"
end

local function vk_show(target, initial)
  -- If a VK is already open, apply its buffer to the current target before switching
  if vk_visible and vk_target then
    if vk_target == 'user' then ss_username = vk_buffer end
    if vk_target == 'pass' then ss_password = vk_buffer end
  end
  vk_target = target
  local current = initial or (target == 'user' and ss_username or ss_password) or ""
  if target == 'user' and current == "USER" then
    vk_buffer = ""
  elseif target == 'pass' and current == "PASS" then
    vk_buffer = ""
  else
    vk_buffer = current
  end
  vk_row, vk_col = 1, 1
  vk_shift = false
  vk_visible = true
  _G.ui_overlay_active = true -- hide global footer while VK is open
end

local function vk_hide(apply)
  if apply and vk_target then
    if vk_target == 'user' then ss_username = vk_buffer end
    if vk_target == 'pass' then ss_password = vk_buffer end
  end
  vk_visible = false
  vk_target = nil
  vk_hold_dir = nil
  vk_hold_time = 0
  vk_repeat_started = false
  vk_hold_acc = 0
  _G.ui_overlay_active = false -- restore footer when VK closes
end

local function vk_current_layout()
  if vk_mode == 'lower' then
    return {
      {"1","2","3","4","5","6","7","8","9","0",{t='back',w=1.6}},
      {"q","w","e","r","t","y","u","i","o","p"},
      {"a","s","d","f","g","h","j","k","l"},
      {"z","x","c","v","b","n","m"},
      {{t='toggle',label='ABC',w=1.8},{t='space',w=3.6},{t='ok',label='OK',w=1.4}},
    }
  elseif vk_mode == 'upper' then
    return {
      {"1","2","3","4","5","6","7","8","9","0",{t='back',w=1.6}},
      {"Q","W","E","R","T","Y","U","I","O","P"},
      {"A","S","D","F","G","H","J","K","L"},
      {"Z","X","C","V","B","N","M"},
      {{t='toggle',label='!@#',w=1.8},{t='space',w=3.6},{t='ok',label='OK',w=1.4}},
    }
  else -- symbol
    return {
      {"!","@","#","$","%","^","&","*","(",")",{t='back',w=1.6}},
      {"`","~","-","_","+","=","{","}","[","]"},
      {"|","\\",":",";","\"","'","!","@","#"},
      {"<",">",",",".","?","/","$"},
      {{t='toggle',label='abc',w=1.8},{t='space',w=3.6},{t='ok',label='OK',w=1.4}},
    }
  end
end

local function vk_handle_key(key)
  if not vk_visible then return false end
  local layout = vk_current_layout()
  if key == 'up' then
    vk_row = math.max(1, vk_row - 1)
    vk_col = math.min(vk_col, #layout[vk_row])
  elseif key == 'down' then
    vk_row = math.min(#layout, vk_row + 1)
    vk_col = math.min(vk_col, #layout[vk_row])
  elseif key == 'left' then
    vk_col = vk_col > 1 and (vk_col - 1) or #layout[vk_row]
  elseif key == 'right' then
    vk_col = vk_col < #layout[vk_row] and (vk_col + 1) or 1
  elseif key == 'confirm' then
    local keydef = layout[vk_row][vk_col]
    if type(keydef) == 'table' then
      if keydef.t == 'space' then vk_buffer = vk_buffer .. ' ' ; if vk_target=='pass' then vk_last_char_time = love.timer.getTime() end
      elseif keydef.t == 'back' then vk_buffer = vk_buffer:sub(1, -2) ; if vk_target=='pass' then vk_last_char_time = 0 end
      elseif keydef.t == 'ok' then vk_hide(true)
      elseif keydef.t == 'toggle' then
        if vk_mode == 'lower' then vk_mode = 'upper'
        elseif vk_mode == 'upper' then vk_mode = 'symbol'
        else vk_mode = 'lower' end
      end
    else
      vk_buffer = vk_buffer .. tostring(keydef)
      if vk_target=='pass' then vk_last_char_time = love.timer.getTime() end
    end
    vk_hold_dir = nil
    return true
  elseif key == 'cancel' then
    vk_hide(false)
    return true
  end
  return key == 'up' or key == 'down' or key == 'left' or key == 'right'
end

local function vk_draw()
  if not vk_visible then return end
  local w, h = w_width, w_height
  -- Keyboard height ~30% of screen and lifted higher to avoid any footer/help bar
  local kb_h = math.floor(h * 0.30)
  local y0 = h - kb_h - 68
  -- Dim the entire screen so VK stands out
  love.graphics.setColor(0, 0, 0, 0.55)
  love.graphics.rectangle('fill', 0, 0, w, h)
  -- Keyboard panel background
  love.graphics.setColor(0, 0, 0, 0.85)
  love.graphics.rectangle('fill', 0, y0, w, kb_h)
  -- Message box just above keys to preview input
  local layout = vk_current_layout()
  local key_w, key_h, margin = 30, 30, 4
  if h >= 720 then key_w, key_h, margin = 38, 38, 6 end
  local box_h = math.max(22, math.floor(key_h * 0.95))
  local box_y = y0 + 6
  local box_x = 10
  local box_w = w - 20
  love.graphics.setColor(0.16, 0.16, 0.16, 1)
  love.graphics.rectangle('fill', box_x, box_y, box_w, box_h, 12, 12)
  love.graphics.setColor(1, 1, 1, 1)
  local preview
  if vk_target == 'pass' then
    local now = love.timer.getTime()
    local n = #vk_buffer
    if n > 0 then
      if vk_last_char_time > 0 and (now - vk_last_char_time) <= vk_last_char_window then
        local visible = vk_buffer:sub(-1)
        preview = string.rep(MASK_CHAR, math.max(0, n-1)) .. visible
      else
        preview = string.rep(MASK_CHAR, n)
      end
    else
      preview = '(enter)'
    end
  else
    preview = (vk_buffer == '' and '(enter)' or vk_buffer)
  end
  love.graphics.printf(preview, box_x + 12, box_y + math.floor((box_h - love.graphics.getFont():getHeight())/2), box_w - 24, 'left')
  -- Keys
  local ypos = box_y + box_h + 10
  local prev_font = love.graphics.getFont()
  love.graphics.setFont(vk_font)

  local function draw_label(cx, cy, kw, kh, text)
    local desired = math.max(14, math.floor(key_h * 0.70))
    if desired ~= vk_char_font_size then
      vk_char_font = love.graphics.newFont(desired)
      vk_char_font_size = desired
    end
    local prev = love.graphics.getFont()
    love.graphics.setFont(vk_char_font)
    local fh = vk_char_font:getHeight()
    local ty = cy + math.floor((kh - fh) / 2)
    love.graphics.printf(text, cx, ty, kw, 'center')
    love.graphics.setFont(prev)
  end
  for r = 1, #layout do
    local row = layout[r]
    local row_w = 0
    for i=1,#row do
      local k = row[i]
      local mult = (type(k)=='table' and k.w) or 1
      row_w = row_w + (key_w*mult) + (i>1 and margin or 0)
    end
    local x = math.floor((w - row_w) / 2)
    local cx = x
    for c = 1, #row do
      local k = row[c]
      local mult = (type(k)=='table' and k.w) or 1
      local kw = key_w * mult
      local rx, ry = cx, ypos + (r - 1) * (key_h + margin)
      if r == vk_row and c == vk_col then
        love.graphics.setColor(0.3, 0.3, 0.8, 1)
        love.graphics.rectangle('fill', rx - 3, ry - 3, kw + 6, key_h + 6, 6, 6)
      end
      love.graphics.setColor(0.2, 0.2, 0.2, 1)
      love.graphics.rectangle('fill', rx, ry, kw, key_h, 4, 4)
      love.graphics.setColor(1, 1, 1, 1)
      if type(k)=='table' then
        if k.t=='toggle' then draw_label(rx, ry, kw, key_h, k.label)
        elseif k.t=='space' then draw_label(rx, ry, kw, key_h, '')
        elseif k.t=='ok' then draw_label(rx, ry, kw, key_h, k.label or 'OK')
        elseif k.t=='back' then
          local img = load_vk_icon('del')
          if img then
            local iw, ih = img:getDimensions()
            local box = math.min(kw * 0.65, key_h * 0.65)
            local sx, sy = box / iw, box / ih
            local mx, my = rx + kw/2, ry + key_h/2
            love.graphics.setColor(1,1,1,1)
            love.graphics.draw(img, mx - (iw * sx) / 2, my - (ih * sy) / 2, 0, sx, sy)
          else
            draw_label(rx, ry, kw, key_h, '⌫')
          end
        else draw_label(rx, ry, kw, key_h, '?') end
      else
        draw_label(rx, ry, kw, key_h, tostring(k))
      end
      cx = cx + kw + margin
    end
  end
  love.graphics.setFont(prev_font)
end


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

local function on_refresh_press()
  user_config:load_platforms()
  user_config:save()
  update_checkboxes()
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
    ss_status = "Saved credentials. Restart Scrappy to apply"
  else
    ss_status = "Enter both username and password."
  end
end

local function on_toggle_show_password()
  ss_show_password = not ss_show_password
end

function settings:load()
  -- Preload Screenscraper credentials (if previously saved)
  load_screenscraper_creds()

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
      + label { text = function() return ss_status end }
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
    height = w_height - 78,
    scroll_speed = 30,
  } + content

  menu = menu + scroller

  -- Position and focus
  menu:updatePosition(10, 10)
  menu:focusFirstElement()
end

function settings:update(dt)
  menu:update(dt)
  if not vk_visible then return end
  local held = nil
  if love.keyboard.isDown('up') then held = 'up'
  elseif love.keyboard.isDown('down') then held = 'down'
  elseif love.keyboard.isDown('left') then held = 'left'
  elseif love.keyboard.isDown('right') then held = 'right' end
  if not held then
    local sticks = love.joystick and love.joystick.getJoysticks and love.joystick.getJoysticks() or {}
    for i = 1, #sticks do
      local j = sticks[i]
      if j:isGamepadDown('dpup') then held = 'up' break end
      if j:isGamepadDown('dpdown') then held = 'down' break end
      if j:isGamepadDown('dpleft') then held = 'left' break end
      if j:isGamepadDown('dpright') then held = 'right' break end
    end
  end
  if held then
    if vk_hold_dir ~= held then
      vk_hold_dir = held
      vk_hold_time = 0
      vk_repeat_started = false
      vk_hold_acc = 0
      vk_handle_key(held)
      return
    end
    vk_hold_time = vk_hold_time + dt
    if not vk_repeat_started then
      if vk_hold_time >= vk_repeat_delay then
        vk_repeat_started = true
        vk_hold_acc = 0
      end
    else
      vk_hold_acc = vk_hold_acc + dt
      while vk_hold_acc >= vk_repeat_rate do
        vk_handle_key(held)
        vk_hold_acc = vk_hold_acc - vk_repeat_rate
      end
    end
  else
    vk_hold_dir = nil
    vk_hold_time = 0
    vk_repeat_started = false
    vk_hold_acc = 0
  end
end

function settings:draw()
  love.graphics.clear(theme:read_color("main", "BACKGROUND", "#000000"))
  menu:draw()
  vk_draw()
end

function settings:keypressed(key)
  -- Map keyboard to VK
  local mapped = nil
  if key == 'up' or key == 'down' or key == 'left' or key == 'right' then mapped = key end
  if key == 'return' then mapped = 'confirm' end
  if key == 'escape' then mapped = 'cancel' end
  if mapped then
    if vk_visible then
      if mapped == 'confirm' or mapped == 'cancel' then
        if vk_handle_key(mapped) then return end
      else
        return
      end
    end
  end

  menu:keypressed(key)
  if key == "escape" or key == "lalt" then
    scenes:pop()
  end
end

function settings:gamepadpressed(joystick, button)
  -- Map gamepad to VK
  local map = {
    dpup = 'up', dpdown = 'down', dpleft = 'left', dpright = 'right',
    a = 'confirm', b = 'cancel'
  }
  local m = map[button]
  if m then
    if vk_visible then
      if m == 'up' or m == 'down' or m == 'left' or m == 'right' then
        return
      else
        if vk_handle_key(m) then return end
      end
    end
  end
  if menu.gamepadpressed then return menu:gamepadpressed(joystick, button) end
end

return settings
