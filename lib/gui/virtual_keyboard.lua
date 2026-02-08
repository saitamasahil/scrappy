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
    repeat_delay = 0.28,
    repeat_rate = 0.06,
    repeat_started = false,
    hold_acc = 0,
    char_font = nil,
    char_font_size = 0,
    last_char_time = 0,
    last_char_window = 0.8,
    move_lock_until = 0,
    opened_at = 0,
  }
  
  function vk:show(initial, target)
    self.buffer = initial or ""
    self.target = target
    self.row, self.col = 1, 1
    self.mode = 'lower'
    self.visible = true
    self.opened_at = love.timer.getTime()
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
    local layout = self:get_layout()
    local now = love.timer.getTime()
    
    local function movement_locked()
      if now < self.move_lock_until then return true end
      if self.opened_at > 0 and (now - self.opened_at) < 0.12 then return true end
      return false
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
    
    if key == 'up' then
      if movement_locked() then return true end
      if self.row == 1 then
        if self.col == 1 then
          self.row = #layout
          self.col = #layout[self.row]
        else
          self.row = #layout
          self.col = math.min(self.col, #layout[self.row])
        end
        self.move_lock_until = love.timer.getTime() + 0.06
        return true
      end
      local target_row = self.row - 1
      if target_row >= 1 then
        self.col = nearest_col_by_x(self.row, self.col, target_row)
        self.row = target_row
        self.move_lock_until = love.timer.getTime() + 0.06
      else
        self.row = 1
        self.col = math.min(self.col, #layout[self.row])
        self.move_lock_until = love.timer.getTime() + 0.06
      end
    elseif key == 'down' then
      if movement_locked() then return true end
      if self.row == #layout then
        self.row = 1
        self.col = math.min(self.col, #layout[self.row])
        self.move_lock_until = love.timer.getTime() + 0.06
        return true
      end
      local target_row = self.row + 1
      if target_row <= #layout then
        self.col = nearest_col_by_x(self.row, self.col, target_row)
        self.row = target_row
        self.move_lock_until = love.timer.getTime() + 0.06
      else
        self.row = #layout
        self.col = math.min(self.col, #layout[self.row])
        self.move_lock_until = love.timer.getTime() + 0.06
      end
    elseif key == 'left' then
      if movement_locked() then return true end
      self.col = self.col > 1 and (self.col - 1) or #layout[self.row]
      self.move_lock_until = love.timer.getTime() + 0.06
    elseif key == 'right' then
      if movement_locked() then return true end
      self.col = self.col < #layout[self.row] and (self.col + 1) or 1
      self.move_lock_until = love.timer.getTime() + 0.06
    elseif key == 'space' then
      self.buffer = self.buffer .. ' '
      if self.mask_input then self.last_char_time = love.timer.getTime() end
      return true
    elseif key == 'backspace' then
      self.buffer = self.buffer:sub(1, -2)
      if self.mask_input then self.last_char_time = 0 end
      return true
    elseif key == 'ok_now' then
      self:hide(true)
      return true
    elseif key == 'confirm' then
      local keydef = layout[self.row][self.col]
      if type(keydef) == 'table' then
        if keydef.t == 'space' then 
          self.buffer = self.buffer .. ' '
          if self.mask_input then self.last_char_time = love.timer.getTime() end
        elseif keydef.t == 'back' then 
          self.buffer = self.buffer:sub(1, -2)
          if self.mask_input then self.last_char_time = 0 end
        elseif keydef.t == 'ok' then 
          self:hide(true)
        elseif keydef.t == 'toggle' then
          if self.mode == 'lower' then self.mode = 'upper'
          elseif self.mode == 'upper' then self.mode = 'symbol'
          else self.mode = 'lower' end
        end
      else
        self.buffer = self.buffer .. tostring(keydef)
        if self.mask_input then self.last_char_time = love.timer.getTime() end
      end
      self.move_lock_until = love.timer.getTime() + 0.08
      self.hold_dir = nil
      return true
    elseif key == 'cancel' then
      self:hide(false)
      return true
    end
    return key == 'up' or key == 'down' or key == 'left' or key == 'right'
  end
  
  function vk:update(dt)
    if not self.visible then return end
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
        while self.hold_acc >= self.repeat_rate do
          self:handle_key(held)
          self.hold_acc = self.hold_acc - self.repeat_rate
        end
      end
    else
      self.hold_dir = nil
      self.hold_time = 0
      self.repeat_started = false
      self.hold_acc = 0
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

    overlay_color[4] = overlay_opacity
    love.graphics.setColor(overlay_color)
    love.graphics.rectangle('fill', 0, 0, w, h)

    panel_bg[4] = panel_opacity
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

    love.graphics.setColor(preview_bg)
    love.graphics.rectangle('fill', box_x, box_y, box_w, box_h, 12, 12)
    love.graphics.setColor(key_text)

    local preview
    if self.mask_input then
      local now = love.timer.getTime()
      local n = #self.buffer
      if n > 0 then
        if self.last_char_time > 0 and (now - self.last_char_time) <= self.last_char_window then
          local visible = self.buffer:sub(-1)
          preview = string.rep(MASK_CHAR, math.max(0, n-1)) .. visible
        else
          preview = string.rep(MASK_CHAR, n)
        end
      else
        preview = self.placeholder
      end
    else
      preview = (self.buffer == '' and self.placeholder or self.buffer)
    end

    love.graphics.printf(preview, box_x + 12, box_y + math.floor((box_h - love.graphics.getFont():getHeight())/2), box_w - 24, 'left')

    -- Draw blinking cursor
    local cursor_blink = math.floor(love.timer.getTime() / 0.53) % 2 == 0
    if cursor_blink then
      local cursor_x = box_x + 12 + love.graphics.getFont():getWidth(preview)
      local cursor_y = box_y + math.floor((box_h - love.graphics.getFont():getHeight())/2)
      local cursor_h = love.graphics.getFont():getHeight()
      love.graphics.setColor(key_text)
      love.graphics.rectangle('fill', cursor_x + 2, cursor_y, 2, cursor_h)
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
        local mult = (type(k)=='table' and k.w) or 1
        local kw = key_w * mult
        local rx, ry = cx, ypos + (r - 1) * (key_h + margin)
        if r == self.row and c == self.col then
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
          else
            draw_label(rx, ry, kw, key_h, '?')
          end
        else
          draw_label(rx, ry, kw, key_h, tostring(k))
        end
        cx = cx + kw + margin
      end
    end
    love.graphics.setFont(prev_font)

    local pw = prompt_w
    local line_h = math.floor(key_h * 0.9)
    local gap_h = 6
    local rows = 2
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
  end
  
  return vk
end

return {
  create = create_vk
}
