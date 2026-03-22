local component = require('lib.gui.badr')
local icon      = require('lib.gui.icon')
local configs   = require('helpers.config')

return function(props)
  local theme = configs.theme
  local font = props.font or love.graphics.getFont()
  local padding = {
    horizontal = (props.leftPadding or 8) + (props.rightPadding or 8),
    vertical = (props.topPadding or 8) + (props.bottomPadding or 8)
  }
  local text = props.text or ""
  local t = love.graphics.newText(font, text)
  local labelWidth, labelHeight = t:getWidth(), t:getHeight()

  local checkboxSize = props.checkboxSize or 16 -- Size of the checkbox square
  local width = math.max(props.width or 0, checkboxSize + padding.horizontal + labelWidth)
  local height = math.max(props.height or 0, checkboxSize + padding.vertical)

  return component {
    text = text,
    checked = props.checked or false,
    id = props.id,
    -- Positioning and layout properties
    x = props.x or 0,
    y = props.y or 0,
    width = width,
    height = height,
    focusable = props.focusable ~= false,
    -- Colors and styles
    -- Colors and styles (explicit overrides only)
    backgroundColor = props.backgroundColor,
    focusColor = props.focusColor,
    checkColor = props.checkColor,
    checkBg = props.checkBg,
    textColor = props.textColor,
    borderWidth = props.borderWidth or 2,
    -- Events
    onToggle = props.onToggle,
    -- Key press handling for toggling checkbox with Enter/Return key
    onKeyPress = function(self, key)
      if (key == "return" or key == "a") and self.focused then
        local now = love.timer.getTime()
        self.last_toggle = self.last_toggle or 0
        if now - self.last_toggle < 0.25 then return end
        self.last_toggle = now
        self.checked = not self.checked
        self.ripple_r = 0
        self.ripple_a = 0.25
        if self.onToggle then self:onToggle(self.checked) end
      end
    end,
    -- Handle mouse clicks
    onClick = function(self)
      if self.disabled then return end
      local now = love.timer.getTime()
      self.last_toggle = self.last_toggle or 0
      if now - self.last_toggle < 0.25 then return end
      self.last_toggle = now
      self.checked = not self.checked
      self.ripple_r = 0
      self.ripple_a = 0.25
      if self.onToggle then self:onToggle(self.checked) end
    end,
    onUpdate = function(self, dt)
      self.anim_p = self.anim_p or (self.focused and 1 or 0)
      local target_p = self.focused and 1 or 0
      self.anim_p = self.anim_p + (target_p - self.anim_p) * 15 * dt

      self.check_p = self.check_p or (self.checked and 1 or 0)
      local check_target = self.checked and 1 or 0
      -- Snappier animation for checking (18x speed for organic feel)
      self.check_p = self.check_p + (check_target - self.check_p) * 18 * dt

      -- Liquid UI: Ripple
      if self.ripple_a and self.ripple_a > 0 then
          self.ripple_r = self.ripple_r + 250 * dt
          self.ripple_a = self.ripple_a - 1.5 * dt
      end
    end,
    draw = function(self)
      if not self.visible then return end

      love.graphics.push()
      -- Scale bump on focus
      local r_width = (self.parent and self.parent.width) or self.width
      local cx, cy = self.x + r_width/2, self.y + self.height/2
      local anim_p = self.anim_p or 0
      local scale = 1.0 + anim_p * 0.02
      love.graphics.translate(cx, cy)
      love.graphics.scale(scale, scale)
      love.graphics.translate(-cx, -cy)

      love.graphics.setFont(font)

      -- Resolve colors dynamically
      local backgroundColor = self.backgroundColor or theme:read_color("checkbox", "CHECKBOX_BACKGROUND", "#000000")
      local focusColor = self.focusColor or theme:read_color("checkbox", "CHECKBOX_FOCUS", "#2d3436")
      local checkColor = self.checkColor or theme:read_color("checkbox", "CHECKBOX_INDICATOR", "#dfe6e9")
      local checkBg = self.checkBg or theme:read_color("checkbox", "CHECKBOX_INDICATOR_BG", "#636e72")
      local textColor = self.textColor or theme:read_color("checkbox", "CHECKBOX_TEXT", "#dfe6e9")

      -- Refresh text object if it changed
      if self.text ~= text then
        text = self.text
        t = love.graphics.newText(font, text)
        labelWidth, labelHeight = t:getWidth(), t:getHeight()
      end

      -- Background and focus styling
      if anim_p > 0.01 then
        local br = backgroundColor[1] + (focusColor[1] - backgroundColor[1]) * anim_p
        local bg = backgroundColor[2] + (focusColor[2] - backgroundColor[2]) * anim_p
        local bb = backgroundColor[3] + (focusColor[3] - backgroundColor[3]) * anim_p
        local ba = (backgroundColor[4] or 1) + ((focusColor[4] or 1) - (backgroundColor[4] or 1)) * anim_p
        love.graphics.setColor(br, bg, bb, ba * anim_p)
        love.graphics.rectangle("fill", self.x, self.y, r_width, self.height, 6)
      end

      -- Inner box for the checkbox background
      love.graphics.setColor(checkBg)
      local bgIcon = icon {
        name = "square",
        x = self.x + padding.horizontal / 2,
        y = self.y + (self.height - checkboxSize) / 2,
        size = checkboxSize
      }
      bgIcon:draw()

      local check_p = self.check_p or (self.checked and 1 or 0)

      -- Liquid UI: Water Fill
      if check_p > 0.001 then
          local fill_h = checkboxSize * check_p
          local fill_y = self.y + (self.height - checkboxSize) / 2 + checkboxSize - fill_h
          local fill_x = self.x + padding.horizontal / 2
          
          love.graphics.setColor(checkColor[1], checkColor[2], checkColor[3], (checkColor[4] or 1) * 0.4)
          -- Draw a slightly rounded water fill
          love.graphics.rectangle("fill", fill_x + 1, fill_y + 1, checkboxSize - 2, fill_h - 2, 2)
          
          -- Surface waves if not full
          if check_p < 0.99 then
              love.graphics.setLineWidth(1)
              local wave_y = fill_y + math.sin(love.timer.getTime() * 12) * 1
              love.graphics.line(fill_x + 2, wave_y, fill_x + checkboxSize - 2, wave_y)
          end
      end

      -- Checkbox mark if checked
      if check_p > 0.5 then
        local mark_iv = (check_p - 0.5) * 2 -- starts appearing after 50% fill
        love.graphics.setColor(checkColor[1], checkColor[2], checkColor[3], (checkColor[4] or 1) * mark_iv)
        love.graphics.push()
        local icon_cx = self.x + padding.horizontal / 2 + checkboxSize / 2
        local icon_cy = self.y + (self.height - checkboxSize) / 2 + checkboxSize / 2
        love.graphics.translate(icon_cx, icon_cy)
        -- Pop-in scale
        local c_scale = 0.2 + mark_iv * 0.8
        love.graphics.scale(c_scale, c_scale)
        love.graphics.translate(-icon_cx, -icon_cy)
        
        local fgIcon = icon {
          name = "square_check",
          x = self.x + padding.horizontal / 2,
          y = self.y + (self.height - checkboxSize) / 2,
          size = checkboxSize
        }
        fgIcon:draw()
        love.graphics.pop()
      end

      -- Liquid UI: Ripple
      if self.ripple_a and self.ripple_a > 0 then
          love.graphics.setColor(textColor[1], textColor[2], textColor[3], self.ripple_a)
          love.graphics.setLineWidth(1)
          local icx = self.x + padding.horizontal / 2 + checkboxSize / 2
          local icy = self.y + self.height / 2
          love.graphics.circle("line", icx, icy, self.ripple_r)
      end

      -- Draw optional icon and label next to the checkbox
      love.graphics.setColor(textColor)
      local currentX = self.x + checkboxSize + padding.horizontal
      if self.icon then
          local iconSize = self.iconSize or 18
          local itemIcon = icon {
              name = self.icon,
              x = currentX,
              y = self.y + (self.height - iconSize) / 2,
              size = iconSize
          }
          itemIcon:draw()
          currentX = currentX + iconSize + 6 -- Add gap after icon
      end
      love.graphics.draw(t, currentX, self.y + (self.height - labelHeight) / 2)

      love.graphics.pop()
    end,
    -- Add icon properties to self
    icon = props.icon,
    iconSize = props.iconSize
  }
end
