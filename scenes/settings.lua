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
-- Larger font for password preview (bigger asterisks)
local vk_password_font = love.graphics.newFont(18)

local settings          = {}

local menu, content, scroller, checkboxes
local info_window

local all_check         = true

-- Screenscraper account state
local ss_username = ""
local ss_password = ""
local ss_show_password = false
local ss_status = ""

-- TheGamesDB API Key Server State
local tgdb_server_running = false
local tgdb_server_ip = nil
local tgdb_server_status = ""
local tgdb_check_timer = 0
local tgdb_key_exists = false
local TMP_TGDB_KEY_FILE = "/tmp/scrappy_tgdb_key.txt"

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
local vk_move_lock_until = 0 -- time until which dpad movement is ignored after confirm
local vk_opened_at = 0       -- timestamp when VK opened; brief grace to ignore movement
local vk_cursor_pos = 0      -- cursor position within text (0 = before first char)
local vk_text_field_focused = false  -- whether text field is focused for cursor movement

-- Optional button prompt icons (A/B)
local INPUT_ICONS = {}
local function load_input_icon(kind)
  if INPUT_ICONS[kind] ~= nil then return INPUT_ICONS[kind] end
  local candidates = {
    "assets/inputs/switch_button_"..kind..".png",
    "assets/inputs/"..kind..".png",
    "assets/inputs/"..kind:upper()..".png",
    "assets/inputs/button_"..kind..".png",
  }
  for _,p in ipairs(candidates) do
    if love.filesystem.getInfo(p) then
      local ok, img = pcall(love.graphics.newImage, p)
      if ok and img then INPUT_ICONS[kind] = img; return img end
    end
  end
  INPUT_ICONS[kind] = false
  return nil
end

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
  vk_opened_at = love.timer.getTime()
  vk_cursor_pos = #vk_buffer  -- Start cursor at end of text
  vk_text_field_focused = false
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
  vk_text_field_focused = false
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
  local now = love.timer.getTime()
  local function movement_locked()
    if now < vk_move_lock_until then return true end
    if vk_opened_at > 0 and (now - vk_opened_at) < 0.12 then return true end
    return false
  end
  
  -- Helper: insert character at cursor position
  local function insert_at_cursor(char)
    local before = vk_buffer:sub(1, vk_cursor_pos)
    local after = vk_buffer:sub(vk_cursor_pos + 1)
    vk_buffer = before .. char .. after
    vk_cursor_pos = vk_cursor_pos + 1
    if vk_target=='pass' then vk_last_char_time = love.timer.getTime() end
  end
  
  -- Helper: delete character before cursor position
  local function delete_at_cursor()
    if vk_cursor_pos > 0 then
      local before = vk_buffer:sub(1, vk_cursor_pos - 1)
      local after = vk_buffer:sub(vk_cursor_pos + 1)
      vk_buffer = before .. after
      vk_cursor_pos = vk_cursor_pos - 1
      if vk_target=='pass' then vk_last_char_time = 0 end
    end
  end
  
  -- Helper: compute nearest column in target row by comparing visual X centers
  local function nearest_col_by_x(src_row_idx, src_col_idx, dst_row_idx)
    local w, h = w_width, w_height
    local key_w, key_h, margin = 30, 30, 4
    if h >= 720 then key_w, key_h, margin = 38, 38, 6 end
    local function row_width(row)
      local rw = 0
      for i=1,#row do
        local k = row[i]
        local mult = (type(k)=='table' and k.w) or 1
        rw = rw + key_w * mult
        if i>1 then rw = rw + margin end
      end
      return rw
    end
    local function col_center_x(row, col)
      local rw = row_width(row)
      local x = math.floor((w - rw) / 2)
      local acc = 0
      for i=1,col do
        local k = row[i]
        local mult = (type(k)=='table' and k.w) or 1
        local kw = key_w * mult
        if i == col then
          return x + acc + kw/2
        end
        acc = acc + kw + margin
      end
      return x + acc -- fallback, shouldn't hit
    end
    local src_row = layout[src_row_idx]
    local dst_row = layout[dst_row_idx]
    local src_cx = col_center_x(src_row, math.min(src_col_idx, #src_row))
    -- Find dst col with closest center x
    local best_col, best_d = 1, math.huge
    local acc = 0
    local rw = row_width(dst_row)
    local x0 = math.floor((w - rw) / 2)
    for i=1,#dst_row do
      local k = dst_row[i]
      local mult = (type(k)=='table' and k.w) or 1
      local kw = key_w * mult
      local cx = x0 + acc + kw/2
      local d = math.abs(cx - src_cx)
      -- Deterministic tie-breaker: prefer the right (higher column) when equal
      if d < best_d or (d == best_d and i > best_col) then
        best_d, best_col = d, i
      end
      acc = acc + kw + margin
    end
    return best_col
  end
  
  -- Handle text field focus mode
  if vk_text_field_focused then
    if key == 'left' then
      if movement_locked() then return true end
      if vk_cursor_pos > 0 then
        vk_cursor_pos = vk_cursor_pos - 1
      end
      vk_move_lock_until = love.timer.getTime() + 0.06
      return true
    elseif key == 'right' then
      if movement_locked() then return true end
      if vk_cursor_pos < #vk_buffer then
        vk_cursor_pos = vk_cursor_pos + 1
      end
      vk_move_lock_until = love.timer.getTime() + 0.06
      return true
    elseif key == 'down' then
      if movement_locked() then return true end
      -- Exit text field focus, go to keyboard row 1
      vk_text_field_focused = false
      vk_row = 1
      vk_move_lock_until = love.timer.getTime() + 0.06
      return true
    elseif key == 'up' then
      if movement_locked() then return true end
      -- Wrap to bottom row of keyboard
      vk_text_field_focused = false
      local layout = vk_current_layout()
      vk_row = #layout
      vk_col = math.min(vk_col, #layout[vk_row])
      vk_move_lock_until = love.timer.getTime() + 0.06
      return true
    elseif key == 'confirm' then
      -- Exit text field focus, go back to keyboard
      vk_text_field_focused = false
      vk_move_lock_until = love.timer.getTime() + 0.08
      return true
    elseif key == 'cancel' then
      vk_hide(false)
      return true
    elseif key == 'backspace' or key == 'y' then
      -- Y button or backspace deletes character at cursor
      delete_at_cursor()
      return true
    elseif key == 'x' then
      -- X button cycles keyboard layout even when text field is focused
      if vk_mode == 'lower' then vk_mode = 'upper'
      elseif vk_mode == 'upper' then vk_mode = 'symbol'
      else vk_mode = 'lower' end
      return true
    end
    return true
  end
  
  -- Normal keyboard navigation
  if key == 'up' then
    if movement_locked() then return true end
    if vk_row == 1 then
      -- From top row, go to text field
      vk_text_field_focused = true
      vk_move_lock_until = love.timer.getTime() + 0.06
      return true
    end
    local target_row = vk_row - 1
    if target_row >= 1 then
      vk_col = nearest_col_by_x(vk_row, vk_col, target_row)
      vk_row = target_row
      vk_move_lock_until = love.timer.getTime() + 0.06
    else
      vk_row = 1
      vk_col = math.min(vk_col, #layout[vk_row])
      vk_move_lock_until = love.timer.getTime() + 0.06
    end
  elseif key == 'down' then
    if movement_locked() then return true end
    if vk_row == #layout then
      vk_row = 1
      vk_col = math.min(vk_col, #layout[vk_row])
      vk_move_lock_until = love.timer.getTime() + 0.06
      return true
    end
    local target_row = vk_row + 1
    if target_row <= #layout then
      vk_col = nearest_col_by_x(vk_row, vk_col, target_row)
      vk_row = target_row
      vk_move_lock_until = love.timer.getTime() + 0.06
    else
      vk_row = #layout
      vk_col = math.min(vk_col, #layout[vk_row])
      vk_move_lock_until = love.timer.getTime() + 0.06
    end
  elseif key == 'left' then
    if movement_locked() then return true end
    vk_col = vk_col > 1 and (vk_col - 1) or #layout[vk_row]
    vk_move_lock_until = love.timer.getTime() + 0.06
  elseif key == 'right' then
    if movement_locked() then return true end
    vk_col = vk_col < #layout[vk_row] and (vk_col + 1) or 1
    vk_move_lock_until = love.timer.getTime() + 0.06
  elseif key == 'space' then
    insert_at_cursor(' ')
    return true
  elseif key == 'backspace' or key == 'y' then
    -- Y button or backspace deletes character at cursor
    delete_at_cursor()
    return true
  elseif key == 'x' then
    -- X button cycles keyboard layout: lower → upper → symbol → lower
    if vk_mode == 'lower' then vk_mode = 'upper'
    elseif vk_mode == 'upper' then vk_mode = 'symbol'
    else vk_mode = 'lower' end
    return true
  elseif key == 'ok_now' then
    vk_hide(true)
    return true
  elseif key == 'confirm' then
    local keydef = layout[vk_row][vk_col]
    if type(keydef) == 'table' then
      if keydef.t == 'space' then insert_at_cursor(' ')
      elseif keydef.t == 'back' then delete_at_cursor()
      elseif keydef.t == 'ok' then vk_hide(true)
      elseif keydef.t == 'toggle' then
        if vk_mode == 'lower' then vk_mode = 'upper'
        elseif vk_mode == 'upper' then vk_mode = 'symbol'
        else vk_mode = 'lower' end
      end
    else
      insert_at_cursor(tostring(keydef))
    end
    -- Short debounce to avoid movement mixing with confirm
    vk_move_lock_until = love.timer.getTime() + 0.08
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

  local overlay_color = theme:read_color("keyboard", "OVERLAY_COLOR", "#000000")
  local overlay_opacity = theme:read_number("keyboard", "OVERLAY_OPACITY", 0.78)
  local panel_bg = theme:read_color("keyboard", "PANEL_BG", "#000000")
  local panel_opacity = theme:read_number("keyboard", "PANEL_OPACITY", 0.85)
  local preview_bg = theme:read_color("keyboard", "PREVIEW_BG", "#292929")
  local key_bg = theme:read_color("keyboard", "KEY_BG", "#333333")
  local key_text = theme:read_color("keyboard", "KEY_TEXT", "#ffffff")
  local key_focus = theme:read_color("keyboard", "KEY_FOCUS", "#4d4dcc")
  local prompt_panel_bg = theme:read_color("keyboard", "PROMPT_PANEL_BG", "#1f1f1f")

  -- Dim the entire screen so VK stands out
  overlay_color[4] = overlay_opacity
  love.graphics.setColor(overlay_color)
  love.graphics.rectangle('fill', 0, 0, w, h)

  -- Keyboard panel background
  panel_bg[4] = panel_opacity
  love.graphics.setColor(panel_bg)
  love.graphics.rectangle('fill', 0, y0, w, h - y0)
  -- Message box just above keys to preview input
  local layout = vk_current_layout()
  local key_w, key_h, margin = 30, 30, 4
  if h >= 720 then key_w, key_h, margin = 38, 38, 6 end
  local prompt_w = 136 -- tighter panel width
  local panel_gap = 12
  local area_x0 = 6 -- shift VK a bit more to the left
  local area_w = math.max(100, w - area_x0 - prompt_w - panel_gap)
  local box_h = math.max(22, math.floor(key_h * 0.95))
  local box_y = y0 + 6
  local box_x = area_x0
  local box_w = area_w
  -- Draw text field focus highlight
  if vk_text_field_focused then
    love.graphics.setColor(key_focus)
    love.graphics.rectangle('line', box_x - 2, box_y - 2, box_w + 4, box_h + 4, 14, 14)
  end

  love.graphics.setColor(preview_bg)
  love.graphics.rectangle('fill', box_x, box_y, box_w, box_h, 12, 12)
  love.graphics.setColor(key_text)

  local preview
  local cursor_display_pos = vk_cursor_pos  -- Position for cursor drawing
  if vk_target == 'pass' then
    local now = love.timer.getTime()
    local n = #vk_buffer
    if n > 0 then
      if vk_last_char_time > 0 and (now - vk_last_char_time) <= vk_last_char_window and vk_cursor_pos > 0 then
        -- Show visible character at cursor position (the character just typed)
        local before_cursor = string.rep(MASK_CHAR, vk_cursor_pos - 1)
        local visible = vk_buffer:sub(vk_cursor_pos, vk_cursor_pos)
        local after_cursor = string.rep(MASK_CHAR, n - vk_cursor_pos)
        preview = before_cursor .. visible .. after_cursor
      else
        preview = string.rep(MASK_CHAR, n)
      end
    else
      preview = '(enter)'
      cursor_display_pos = 0
    end
  else
    if vk_buffer == '' then
      preview = '(enter)'
      cursor_display_pos = 0
    else
      preview = vk_buffer
    end
  end
  -- For password, use larger font for better asterisk visibility
  local preview_font = (vk_target == 'pass' and vk_buffer ~= '') and vk_password_font or love.graphics.getFont()
  local prev_font = love.graphics.getFont()
  love.graphics.setFont(preview_font)
  -- Asterisk has high baseline, so add offset for password to center it visually
  local y_offset = (vk_target == 'pass' and vk_buffer ~= '') and math.floor(preview_font:getHeight() * 0.15) or 0
  love.graphics.printf(preview, box_x + 12, box_y + math.floor((box_h - preview_font:getHeight())/2) + y_offset, box_w - 24, 'left')

  -- Draw blinking cursor at the correct position
  local cursor_blink = math.floor(love.timer.getTime() / 0.53) % 2 == 0
  if cursor_blink or vk_text_field_focused then
    -- Calculate cursor X based on cursor position, using actual preview text
    local text_before_cursor
    if vk_target == 'pass' and #vk_buffer > 0 then
      -- Use the actual preview text up to cursor position for accurate width
      text_before_cursor = preview:sub(1, math.min(cursor_display_pos, #preview))
    else
      text_before_cursor = vk_buffer:sub(1, cursor_display_pos)
    end
    local cursor_x = box_x + 12 + preview_font:getWidth(text_before_cursor)
    local cursor_y = box_y + math.floor((box_h - preview_font:getHeight())/2) + y_offset
    local cursor_h = preview_font:getHeight()
    love.graphics.setColor(key_text)
    love.graphics.rectangle('fill', cursor_x, cursor_y, 2, cursor_h)
  end
  love.graphics.setFont(prev_font)

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
    local x = area_x0 + math.floor((area_w - row_w) / 2)
    local cx = x
    for c = 1, #row do
      local k = row[c]
      local mult = (type(k)=='table' and k.w) or 1
      local kw = key_w * mult
      local rx, ry = cx, ypos + (r - 1) * (key_h + margin)
      if r == vk_row and c == vk_col and not vk_text_field_focused then
        love.graphics.setColor(key_focus)
        love.graphics.rectangle('fill', rx - 3, ry - 3, kw + 6, key_h + 6, 6, 6)
      end
      love.graphics.setColor(key_bg)
      love.graphics.rectangle('fill', rx, ry, kw, key_h, 4, 4)
      love.graphics.setColor(key_text)
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
            love.graphics.setColor(key_text)
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

  -- Button prompts panel (right side)
  local pw = prompt_w
  -- Compact panel sized for two lines (A/B)
  local line_h = math.floor(key_h * 0.9)
  local gap_h = 6
  local rows = 4  -- A, B, X, Y
  local ph = 8 + rows * line_h + (rows - 1) * gap_h + 8
  local right_margin = 36
  local px = area_x0 + area_w + panel_gap - right_margin
  -- Center within the space below the preview box; bias slightly lower
  local avail_top = box_y + box_h + 6
  local avail_bottom = h - 6
  local centered_py = math.floor((avail_top + avail_bottom - ph) / 2)
  local py = math.max(avail_top, centered_py + 6)
  if py + ph > avail_bottom then py = avail_bottom - ph end
  love.graphics.setColor(prompt_panel_bg)
  love.graphics.rectangle('fill', px, py, pw, ph, 12, 12)
  love.graphics.setColor(key_text)

  local function draw_prompt(row_i, icon_key, text)
    local ly = py + 8 + (row_i-1) * (line_h + gap_h)
    local icon = load_input_icon(icon_key)
    local ix = px + 10
    local iy = ly
    local iw = line_h
    local ih = line_h
    if icon then
      local w0,h0 = icon:getDimensions()
      local sx, sy = iw / w0, ih / h0
      love.graphics.draw(icon, ix, iy, 0, sx, sy)
    else
      love.graphics.rectangle('line', ix, iy, iw, ih, 6, 6)
      love.graphics.printf(icon_key:upper(), ix, iy + ih*0.25, iw, 'center')
    end
    love.graphics.printf(text, ix + iw + 10, iy + math.floor((ih - love.graphics.getFont():getHeight())/2), pw - (iw + 20), 'left')
  end

  draw_prompt(1, 'a', 'Confirm')
  draw_prompt(2, 'b', 'Close')
  draw_prompt(3, 'x', 'Layout')
  draw_prompt(4, 'y', 'Delete')
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
    ss_status = "Saved credentials."
  else
    ss_status = "Enter both username and password."
  end
end

local function on_toggle_show_password()
  ss_show_password = not ss_show_password
end

local function on_enter_tgdb_key_web()
  if tgdb_server_running then
    -- Cancel server
    os.execute("pkill -f tgdb_server.py")
    tgdb_server_running = false
    tgdb_server_status = "Server stopped."
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
    tgdb_server_status = "Go to http://" .. ip .. ":8080 on your phone/PC"
    tgdb_check_timer = 0
  else
    tgdb_server_status = "Could not find IP address! Connect to WiFi."
  end
end

function settings:load()
  -- Preload Screenscraper credentials (if previously saved)
  load_screenscraper_creds()
  
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
      + label { text = function() return ss_status end }
      
      + label { text = 'TheGamesDB Account', icon = "user" }
      + (component { column = true, gap = 6 }
          + button { 
              text = function() 
                if tgdb_server_running then
                  return 'Cancel / Stop Server'
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
      + label { text = function() return tgdb_server_status end }
      
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
  if info_window and info_window.visible then
    info_window:update(dt)
  else
    menu:update(dt)
  end
  
  if tgdb_server_running then
    tgdb_check_timer = tgdb_check_timer + dt
    -- Check every 1 second
    if tgdb_check_timer >= 1.0 then
      tgdb_check_timer = 0
      
      -- Check if file exists via nativefs or standard io
      local f = io.open(TMP_TGDB_KEY_FILE, "r")
      if f then
        local key = f:read("*a")
        f:close()
        if key and key ~= "" then
          local sk = configs.skyscraper_config
          -- Save with quotes
          sk:insert('thegamesdb', 'userCreds', '"' .. key:gsub("%s+", "") .. '"')
          sk:save()
          sk:sync_native_config()
          tgdb_key_exists = true
          tgdb_server_status = "Key saved successfully!"
          tgdb_server_running = false
          -- Server shuts itself down, but we can ensure cleanup
          os.remove(TMP_TGDB_KEY_FILE)
        end
      end
    end
  end

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
  if info_window and info_window.visible then
    info_window:draw()
  end
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
  -- Map gamepad to VK (A/B/X/Y and D-Pad)
  local map = {
    dpup = 'up', dpdown = 'down', dpleft = 'left', dpright = 'right',
    a = 'confirm', b = 'cancel', x = 'x', y = 'y'
  }
  local btn = type(button) == 'string' and button:lower() or button
  local m = map[btn] or map[button]
  if m then
    if vk_visible then
      if m == 'up' or m == 'down' or m == 'left' or m == 'right' then
        return true  -- VK will handle D-pad via update()
      else
        if vk_handle_key(m) then return true end
      end
    end
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
