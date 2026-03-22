-- Virtual keyboard module for gamepad/keyboard text input
-- Extracted from settings.lua for reuse across scenes

local w_width, w_height = love.window.getMode()
local configs = require("helpers.config")

-- Virtual keyboard layout
local MASK_CHAR = "*"

-- Smaller font for virtual keyboard labels
local vk_font = love.graphics.newFont(12)

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

-- Optional pixel icon support for special keys
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

-- Create a new virtual keyboard instance
local function create_vk(config)
  config = config or {}
  
  local vk = {
    visible = false,
    mode = 'lower', -- lower | upper | symbol
    row = 1,
    col = 1,
    buffer = "",
    target = nil, -- custom target identifier
    on_done = config.on_done,
    on_cancel = config.on_cancel,
    placeholder = config.placeholder or "(enter)",
    mask_input = config.mask_input or false,
    title = config.title or "",
    
    -- Timing state
    hold_dir = nil,
    hold_time = 0,
    repeat_delay = 0.45,
    repeat_rate = 0.12,
    nav_repeat_rate = 0.08, -- Faster rate for D-pad navigation
    repeat_started = false,
    hold_acc = 0,
    char_font = nil,
    char_font_size = 0,
    last_char_time = 0,
    last_char_window = 0.8,
    move_lock_until = 0,
    opened_at = 0,
    
    -- Cursor position within text (0 = before first char, #buffer = after last char)
    cursor_pos = 0,
    -- Whether the text field is focused (for cursor movement within text)
    text_field_focused = false,
    key_anim = {},
    key_ripples = {}, -- [row][col] = {r, a}
    key_squish = {},  -- [row][col] = {sx, sy}
    -- Focus flow animation states
    focus_x = 0, focus_y = 0, focus_w = 0, focus_h = 0,
    focus_initialized = false,
  }
  
  function vk:show(initial, target)
    self.buffer = initial or ""
    self.target = target
    self.row, self.col = 1, 1
    self.mode = 'lower'
    self.visible = true
    self.opened_at = love.timer.getTime()
    self.cursor_pos = #self.buffer  -- Start cursor at end of text
    self.text_field_focused = false
    self.focus_initialized = false -- reset so it snaps to first key on show
    self.fade = 0
    _G.ui_overlay_active = true
  end
  
  function vk:hide(apply)
    if apply and self.on_done then
      self.on_done(self.buffer, self.target)
    elseif not apply and self.on_cancel then
      self.on_cancel(self.target)
    end
    self.visible = false
    self.target = nil
    self.hold_dir = nil
    self.hold_time = 0
    self.repeat_started = false
    self.hold_acc = 0
    _G.ui_overlay_active = false
  end
  
  function vk:get_layout()
    if self.mode == 'lower' then
      return {
        {"1","2","3","4","5","6","7","8","9","0",{t='back',w=1.6}},
        {"q","w","e","r","t","y","u","i","o","p"},
        {"a","s","d","f","g","h","j","k","l"},
        {"z","x","c","v","b","n","m"},
        {{t='toggle',label='ABC',w=1.8},{t='space',w=3.6},{t='ok',label='OK',w=1.4}},
      }
    elseif self.mode == 'upper' then
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
  
  function vk:handle_key(key)
    if not self.visible then return false end
    if key == 'return' or key == 'kpreturn' then key = 'confirm' end
    local layout = self:get_layout()
    local now = love.timer.getTime()
    
    local function movement_locked()
      if now < self.move_lock_until then return true end
      if self.opened_at > 0 and (now - self.opened_at) < 0.12 then return true end
      return false
    end
    
    -- Helper: insert character at cursor position
    local function insert_at_cursor(char)
      local before = self.buffer:sub(1, self.cursor_pos)
      local after = self.buffer:sub(self.cursor_pos + 1)
      self.buffer = before .. char .. after
      self.cursor_pos = self.cursor_pos + 1
      if self.mask_input then self.last_char_time = love.timer.getTime() end
    end
    
    -- Helper: delete character before cursor position
    local function delete_at_cursor()
      if self.cursor_pos > 0 then
        local before = self.buffer:sub(1, self.cursor_pos - 1)
        local after = self.buffer:sub(self.cursor_pos + 1)
        self.buffer = before .. after
        self.cursor_pos = self.cursor_pos - 1
        if self.mask_input then self.last_char_time = 0 end
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
        return x + acc
      end
      local src_row = layout[src_row_idx]
      local dst_row = layout[dst_row_idx]
      local src_cx = col_center_x(src_row, math.min(src_col_idx, #src_row))
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
        if d < best_d or (d == best_d and i > best_col) then
          best_d, best_col = d, i
        end
        acc = acc + kw + margin
      end
      return best_col
    end
    
    -- Handle text field focus mode
    if self.text_field_focused then
      if key == 'left' then
        if movement_locked() then return true end
        if self.cursor_pos > 0 then
          self.cursor_pos = self.cursor_pos - 1
        end
        self.move_lock_until = love.timer.getTime() + 0.12
        return true
      elseif key == 'right' then
        if movement_locked() then return true end
        if self.cursor_pos < #self.buffer then
          self.cursor_pos = self.cursor_pos + 1
        end
        self.move_lock_until = love.timer.getTime() + 0.12
        return true
      elseif key == 'down' then
        if movement_locked() then return true end
        -- Exit text field focus, go to keyboard row 1
        self.text_field_focused = false
        self.row = 1
        self.move_lock_until = love.timer.getTime() + 0.12
        return true
      elseif key == 'up' then
        if movement_locked() then return true end
        -- Wrap to bottom row of keyboard
        self.text_field_focused = false
        local layout = self:get_layout()
        self.row = #layout
        self.col = math.min(self.col, #layout[self.row])
        self.move_lock_until = love.timer.getTime() + 0.12
        return true
      elseif key == 'confirm' then
        -- Exit text field focus, go back to keyboard
        self.text_field_focused = false
        self.move_lock_until = love.timer.getTime() + 0.12
        return true
      elseif key == 'cancel' then
        self:hide(false)
        return true
      elseif key == 'backspace' or key == 'y' then
        if movement_locked() then return true end
        -- Y button or backspace deletes character at cursor
        delete_at_cursor()
        self.move_lock_until = love.timer.getTime() + 0.12
        return true
      elseif key == 'x' then
        if movement_locked() then return true end
        -- X button cycles keyboard layout even when text field is focused
        if self.mode == 'lower' then self.mode = 'upper'
        elseif self.mode == 'upper' then self.mode = 'symbol'
        else self.mode = 'lower' end
        self.move_lock_until = love.timer.getTime() + 0.12
        return true
      end
      return true
    end
    
    -- Normal keyboard navigation
    if key == 'up' then
      if movement_locked() then return true end
      if self.row == 1 then
        -- From top row, go to text field
        self.text_field_focused = true
        self.move_lock_until = love.timer.getTime() + 0.12
        return true
      end
      local target_row = self.row - 1
      if target_row >= 1 then
        self.col = nearest_col_by_x(self.row, self.col, target_row)
        self.row = target_row
        self.move_lock_until = love.timer.getTime() + self.nav_repeat_rate
      else
        self.row = 1
        self.col = math.min(self.col, #layout[self.row])
        self.move_lock_until = love.timer.getTime() + self.nav_repeat_rate
      end
    elseif key == 'down' then
      if movement_locked() then return true end
      if self.row == #layout then
        self.row = 1
        self.col = math.min(self.col, #layout[self.row])
        self.move_lock_until = love.timer.getTime() + self.nav_repeat_rate
        return true
      end
      local target_row = self.row + 1
      if target_row <= #layout then
        self.col = nearest_col_by_x(self.row, self.col, target_row)
        self.row = target_row
        self.move_lock_until = love.timer.getTime() + self.nav_repeat_rate
      else
        self.row = #layout
        self.col = math.min(self.col, #layout[self.row])
        self.move_lock_until = love.timer.getTime() + self.nav_repeat_rate
      end
    elseif key == 'left' then
      if movement_locked() then return true end
      self.col = self.col > 1 and (self.col - 1) or #layout[self.row]
      self.move_lock_until = love.timer.getTime() + self.nav_repeat_rate
    elseif key == 'right' then
      if movement_locked() then return true end
      self.col = self.col < #layout[self.row] and (self.col + 1) or 1
      self.move_lock_until = love.timer.getTime() + self.nav_repeat_rate
    elseif key == 'space' then
      if movement_locked() then return true end
      insert_at_cursor(' ')
      return true
    elseif key == 'backspace' or key == 'y' then
      if movement_locked() then return true end
      -- Y button or backspace deletes character at cursor
      delete_at_cursor()
      self.move_lock_until = love.timer.getTime() + 0.12
      return true
    elseif key == 'x' then
      if movement_locked() then return true end
      -- X button cycles keyboard layout: lower → upper → symbol → lower
      if self.mode == 'lower' then self.mode = 'upper'
      elseif self.mode == 'upper' then self.mode = 'symbol'
      else self.mode = 'lower' end
      self.move_lock_until = love.timer.getTime() + 0.12
      return true
    elseif key == 'ok_now' then
      self:hide(true)
      return true
    elseif key == 'confirm' then
      if movement_locked() then return true end
      local keydef = layout[self.row][self.col]
      if type(keydef) == 'table' then
        if keydef.t == 'space' then 
          insert_at_cursor(' ')
        elseif keydef.t == 'back' then 
          delete_at_cursor()
        elseif keydef.t == 'ok' then 
          self:hide(true)
        elseif keydef.t == 'toggle' then
          if self.mode == 'lower' then self.mode = 'upper'
          elseif self.mode == 'upper' then self.mode = 'symbol'
          else self.mode = 'lower' end
        end
      else
        insert_at_cursor(tostring(keydef))
      end
      self.move_lock_until = love.timer.getTime() + 0.12
      self.hold_dir = nil
      
      -- Trigger ripple and squish
      self.key_ripples[self.row] = self.key_ripples[self.row] or {}
      self.key_ripples[self.row][self.col] = { r = 0, a = 0.6 }
      
      return true
    elseif key == 'cancel' then
      self:hide(false)
      return true
    end
    return key == 'up' or key == 'down' or key == 'left' or key == 'right'
  end
  
  function vk:update(dt)
    if not self.visible then 
      self.fade = 0
      return 
    end
    -- Organic opening curve (aggressive EaseOut)
    self.fade = (self.fade or 0) + (1 - (self.fade or 0)) * 12 * dt
    if self.fade > 0.999 then self.fade = 1 end
    
    self.icon_scales = self.icon_scales or { a = 1, b = 1, x = 1, y = 1, dpad = 1 }
    local icon_input = require("helpers.input")
    local hold_keys = { a = "return", b = "escape", x = "x", y = "y", dpad = "up" }
    
    for k, v in pairs(hold_keys) do
        local pressed = false
        if k == "dpad" then
            pressed = icon_input.isEventDown("up") or icon_input.isEventDown("down") or icon_input.isEventDown("left") or icon_input.isEventDown("right")
        else
            pressed = icon_input.isEventDown(v)
        end
        if pressed then
            self.icon_scales[k] = self.icon_scales[k] + (0.6 - self.icon_scales[k]) * 30 * dt
        else
            self.icon_scales[k] = self.icon_scales[k] + (1 - self.icon_scales[k]) * 15 * dt
        end
    end
    
    local held = nil
    if icon_input.isEventDown('up') then held = 'up'
    elseif icon_input.isEventDown('down') then held = 'down'
    elseif icon_input.isEventDown('left') then held = 'left'
    elseif icon_input.isEventDown('right') then held = 'right' 
    elseif icon_input.isEventDown('return') then held = 'confirm'
    elseif icon_input.isEventDown('x') then held = 'x'
    elseif icon_input.isEventDown('y') then held = 'backspace' end
    if held then
      if self.hold_dir ~= held then
        self.hold_dir = held
        self.hold_time = 0
        self.repeat_started = false
        self.hold_acc = 0
        self:handle_key(held)
        return
      end
      self.hold_time = self.hold_time + dt
      if not self.repeat_started then
        if self.hold_time >= self.repeat_delay then
          self.repeat_started = true
          self.hold_acc = 0
        end
      else
        self.hold_acc = self.hold_acc + dt
        local current_rate = self.repeat_rate
        if held == 'up' or held == 'down' or held == 'left' or held == 'right' then
          current_rate = self.nav_repeat_rate
        end
        while self.hold_acc >= current_rate do
          self:handle_key(held)
          self.hold_acc = self.hold_acc - current_rate
        end
      end
    else
      self.hold_dir = nil
      self.hold_time = 0
      self.repeat_started = false
      self.hold_acc = 0
    end

    -- Update individual key animations and focus flow
    local layout = self:get_layout()
    local key_w, key_h, margin = 30, 30, 4
    if w_height >= 720 then key_w, key_h, margin = 38, 38, 6 end
    local kb_h = math.floor(w_height * 0.30)
    local y0 = w_height - kb_h - 68
    local box_h = math.max(22, math.floor(key_h * 0.95))
    local box_y = y0 + 6
    local area_x0 = 6
    local prompt_w = 136
    local panel_gap = 12
    local area_w = math.max(100, w_width - area_x0 - prompt_w - panel_gap)
    local keys_y0 = box_y + box_h + 10

    local target_x, target_y, target_w, target_h = 0, 0, 0, 0

    if self.text_field_focused then
      target_x, target_y = area_x0, box_y
      target_w, target_h = area_w, box_h
    end

    for r = 1, #layout do
      local row = layout[r]
      local row_w = 0
      for i=1,#row do
        local k = row[i]
        local mult = (type(k)=='table' and k.w) or 1
        row_w = row_w + (key_w*mult) + (i>1 and margin or 0)
      end
      local x_start = area_x0 + math.floor((area_w - row_w) / 2)
      local cx = x_start
      
      self.key_anim[r] = self.key_anim[r] or {}
      for c = 1, #row do
        local k = row[c]
        local mult = (type(k)=='table' and k.w) or 1
        local kw = key_w * mult
        local ry = keys_y0 + (r - 1) * (key_h + margin)
        
        local is_focused = (not self.text_field_focused and self.row == r and self.col == c)
        local target_v = is_focused and 1 or 0
        self.key_anim[r][c] = (self.key_anim[r][c] or 0) + (target_v - (self.key_anim[r][c] or 0)) * 20 * dt
        
        -- Liquid Squish for keys
        self.key_squish[r] = self.key_squish[r] or {}
        self.key_squish[r][c] = self.key_squish[r][c] or { sx = 1, sy = 1 }
        local is_pressed = is_focused and held == 'confirm'
        local target_sx = is_pressed and 1.15 or 1
        local target_sy = is_pressed and 0.82 or 1
        local ks = self.key_squish[r][c]
        ks.sx = ks.sx + (target_sx - ks.sx) * 25 * dt
        ks.sy = ks.sy + (target_sy - ks.sy) * 25 * dt
        
        -- Liquid Ripple for keys
        self.key_ripples[r] = self.key_ripples[r] or {}
        local kr = self.key_ripples[r][c]
        if kr and kr.a > 0 then
            kr.r = kr.r + 200 * dt
            kr.a = kr.a - 2.0 * dt
        end

        if is_focused then
          target_x, target_y = cx, ry
          target_w, target_h = kw, key_h
        end
        cx = cx + kw + margin
      end
    end

    -- Lerp focus flow
    if not self.focus_initialized then
      self.focus_x, self.focus_y = target_x, target_y
      self.focus_w, self.focus_h = target_w, target_h
      self.focus_initialized = true
    else
      local speed = 15
      self.focus_x = self.focus_x + (target_x - self.focus_x) * speed * dt
      self.focus_y = self.focus_y + (target_y - self.focus_y) * speed * dt
      self.focus_w = self.focus_w + (target_w - self.focus_w) * speed * dt
      self.focus_h = self.focus_h + (target_h - self.focus_h) * speed * dt
    end
  end

  function vk:draw()
    if not self.visible then return end
    local w, h = w_width, w_height
    local kb_h = math.floor(h * 0.30)
    local y0 = h - kb_h - 68

    local theme = configs.theme

    local overlay_color = theme:read_color("keyboard", "OVERLAY_COLOR", "#000000")
    local overlay_opacity = theme:read_number("keyboard", "OVERLAY_OPACITY", 0.78)
    local panel_bg = theme:read_color("keyboard", "PANEL_BG", "#000000")
    local panel_opacity = theme:read_number("keyboard", "PANEL_OPACITY", 0.85)
    local preview_bg = theme:read_color("keyboard", "PREVIEW_BG", "#292929")
    local key_bg = theme:read_color("keyboard", "KEY_BG", "#333333")
    local key_text = theme:read_color("keyboard", "KEY_TEXT", "#ffffff")
    local key_focus = theme:read_color("keyboard", "KEY_FOCUS", "#4d4dcc")
    local prompt_panel_bg = theme:read_color("keyboard", "PROMPT_PANEL_BG", "#1f1f1f")

    local fade = self.fade or 1
    overlay_color[4] = overlay_opacity * fade
    love.graphics.setColor(overlay_color)
    love.graphics.rectangle('fill', 0, 0, w, h)

    love.graphics.push()
    love.graphics.translate(0, (1 - fade) * 20)

    panel_bg[4] = panel_opacity * fade
    love.graphics.setColor(panel_bg)
    love.graphics.rectangle('fill', 0, y0, w, h - y0)

    local layout = self:get_layout()
    local key_w, key_h, margin = 30, 30, 4
    if h >= 720 then key_w, key_h, margin = 38, 38, 6 end
    local prompt_w = 136
    local panel_gap = 12
    local area_x0 = 6
    local area_w = math.max(100, w - area_x0 - prompt_w - panel_gap)
    local box_h = math.max(22, math.floor(key_h * 0.95))
    local box_y = y0 + 6
    local box_x = area_x0
    local box_w = area_w

    -- Draw a modern, soft sliding focus highlight that glides between keys
    if self.focus_w and self.focus_w > 0 then
      local padding = 4
      love.graphics.setColor(key_focus[1], key_focus[2], key_focus[3], (key_focus[4] or 1) * 0.35)
      love.graphics.rectangle('fill', self.focus_x - padding, self.focus_y - padding, self.focus_w + padding*2, self.focus_h + padding*2, 10, 10)
    end
    
    love.graphics.setColor(preview_bg)
    love.graphics.rectangle('fill', box_x, box_y, box_w, box_h, 12, 12)
    
    if self.text_field_focused then
      love.graphics.setLineWidth(2)
      love.graphics.setColor(key_focus)
      love.graphics.rectangle('line', box_x - 1, box_y - 1, box_w + 2, box_h + 2, 12, 12)
      love.graphics.setLineWidth(1)
    end
    
    love.graphics.setColor(key_text)

    local preview
    local cursor_display_pos = self.cursor_pos  -- Position for cursor drawing
    if self.mask_input then
      local now = love.timer.getTime()
      local n = #self.buffer
      if n > 0 then
        if self.last_char_time > 0 and (now - self.last_char_time) <= self.last_char_window and self.cursor_pos > 0 then
          -- Show visible character at cursor position (the character just typed)
          local before_cursor = string.rep(MASK_CHAR, self.cursor_pos - 1)
          local visible = self.buffer:sub(self.cursor_pos, self.cursor_pos)
          local after_cursor = string.rep(MASK_CHAR, n - self.cursor_pos)
          preview = before_cursor .. visible .. after_cursor
        else
          preview = string.rep(MASK_CHAR, n)
        end
      else
        preview = self.placeholder
        cursor_display_pos = 0
      end
    else
      if self.buffer == '' then
        preview = self.placeholder
        cursor_display_pos = 0
      else
        preview = self.buffer
      end
    end

    love.graphics.printf(preview, box_x + 12, box_y + math.floor((box_h - love.graphics.getFont():getHeight())/2), box_w - 24, 'left')

    -- Draw blinking cursor at the correct position
    local cursor_blink = math.floor(love.timer.getTime() / 0.53) % 2 == 0
    if cursor_blink or self.text_field_focused then
      -- Calculate cursor X based on cursor position, not end of text
      -- Calculate cursor X based on exactly what was printed before the cursor
      local text_before_cursor = preview:sub(1, cursor_display_pos)
      local cursor_x = box_x + 12 + love.graphics.getFont():getWidth(text_before_cursor)
      local cursor_y = box_y + math.floor((box_h - love.graphics.getFont():getHeight())/2)
      local cursor_h = love.graphics.getFont():getHeight()
      love.graphics.setColor(key_text)
      love.graphics.rectangle('fill', cursor_x, cursor_y, 2, cursor_h)
    end

    local ypos = box_y + box_h + 10
    local prev_font = love.graphics.getFont()
    love.graphics.setFont(vk_font)

    local function draw_label(cx, cy, kw, kh, text)
      local desired = math.max(14, math.floor(key_h * 0.70))
      if desired ~= self.char_font_size then
        self.char_font = love.graphics.newFont(desired)
        self.char_font_size = desired
      end
      local prev = love.graphics.getFont()
      love.graphics.setFont(self.char_font)
      local fh = self.char_font:getHeight()
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
        local anim_p = (self.key_anim[r] and self.key_anim[r][c]) or 0
        local mult = (type(k)=='table' and k.w) or 1
        local kw = key_w * mult
        local rx, ry = cx, ypos + (r - 1) * (key_h + margin)
        
        love.graphics.push()
        local kcx, kcy = rx + kw/2, ry + key_h/2
        local kscale = 1.0 + anim_p * 0.09
        local ks = (self.key_squish[r] and self.key_squish[r][c]) or {sx=1, sy=1}
        love.graphics.translate(kcx, kcy)
        love.graphics.scale(kscale * ks.sx, kscale * ks.sy)
        love.graphics.translate(-kcx, -kcy)

        local current_bg = key_bg
        if anim_p > 0.01 then
          -- Blend to focus color based on animation progress
          local br = key_bg[1] + (key_focus[1] - key_bg[1]) * anim_p
          local bg = key_bg[2] + (key_focus[2] - key_bg[2]) * anim_p
          local bb = key_bg[3] + (key_focus[3] - key_bg[3]) * anim_p
          local ba = (key_bg[4] or 1) + ((key_focus[4] or 1) - (key_bg[4] or 1)) * anim_p
          current_bg = {br, bg, bb, ba}
        end
        
        love.graphics.setColor(current_bg)
        love.graphics.rectangle('fill', rx, ry, kw, key_h, 6, 6)
        
        -- Draw key ripple
        local kr = (self.key_ripples[r] and self.key_ripples[r][c])
        if kr and kr.a > 0 then
            love.graphics.setColor(key_text[1], key_text[2], key_text[3], kr.a)
            love.graphics.setLineWidth(1)
            love.graphics.circle("line", kcx, kcy, kr.r)
        end

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
          else
            draw_label(rx, ry, kw, key_h, '?')
          end
        else
          draw_label(rx, ry, kw, key_h, tostring(k))
        end
        love.graphics.pop()
        cx = cx + kw + margin
      end
    end
    love.graphics.setFont(prev_font)

    local pw = prompt_w
    local line_h = math.floor(key_h * 0.9)
    local gap_h = 6
    local rows = 4  -- A, B, X, Y
    local ph = 8 + rows * line_h + (rows - 1) * gap_h + 8
    local right_margin = 36
    local px = area_x0 + area_w + panel_gap - right_margin
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
        local scale_mult = self.icon_scales and self.icon_scales[icon_key] or 1
        local sx, sy = (iw / w0) * scale_mult, (ih / h0) * scale_mult
        local cx, cy = ix + iw / 2, iy + ih / 2
        love.graphics.draw(icon, cx - (w0 * sx) / 2, cy - (h0 * sy) / 2, 0, sx, sy)
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
    love.graphics.pop()
  end
  
  return vk
end

return {
  create = create_vk
}
