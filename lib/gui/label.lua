local component = require("lib.gui.badr")
local icon      = require("lib.gui.icon")
local configs   = require("helpers.config")

local icon_to_event = {
  ["button_a"] = "return",
  ["button_b"] = "escape",
  ["button_x"] = "x",
  ["button_y"] = "y",
  ["select"] = "lalt",
  ["dpad"] = {"up", "down"},
  ["dpad_horizontal"] = {"left", "right"}
}

local function label(props)
  local _font = props.font or love.graphics.getFont()
  local color = props.color
  local iconSize = 20
  local padding = props.iconPadding or 4
  -- Support dynamic labels: if props.text is a function, call it on draw; otherwise use self.text
  local get_text = (type(props.text) == "function") and props.text or nil
  local initial_text = (get_text and get_text()) or (props.text or "")
  local textWidth = _font:getWidth(initial_text)
  local textHeight = _font:getHeight()
  local totalWidth = textWidth
  if props.iconName then
    totalWidth = totalWidth + iconSize + padding
  end

  return component {
    text = initial_text,
    get_text = get_text,
    visible = props.visible,
    id = props.id,
    x = props.x or 0,
    y = props.y or 0,
    width = props.max_width or totalWidth,
    max_width = props.max_width,
    height = textHeight,
    font = _font,
    icon = props.icon,
    trigger_bounce = function(self)
        self.icon_scale = 0.6 -- Fallback trigger, but normally self-driven now
    end,
    onUpdate = function(self, dt)
        self.icon_scale = self.icon_scale or 1
        
        local first_press = false
        local pressed = false
        if self.icon and icon_to_event[self.icon] then
            local icon_input = require("helpers.input")
            local ev = icon_to_event[self.icon]
            if type(ev) == "table" then
                for _, e in ipairs(ev) do
                    if icon_input.isEventJustPressed and icon_input.isEventJustPressed(e) then
                        first_press = true
                        break
                    end
                    if icon_input.isEventDown and icon_input.isEventDown(e) then
                        pressed = true
                    end
                end
            else
                if icon_input.isEventJustPressed and icon_input.isEventJustPressed(ev) then
                    first_press = true
                end
                if icon_input.isEventDown and icon_input.isEventDown(ev) then
                    pressed = true
                end
            end
        end
        
        if first_press then
            self.ripple_r = 0
            self.ripple_a = 0.25
        end
        if self.ripple_a and self.ripple_a > 0 then
            self.ripple_r = self.ripple_r + 250 * dt
            self.ripple_a = self.ripple_a - 1.5 * dt
        end

        if pressed then
            -- Snap down quickly while held
            self.icon_scale = self.icon_scale + (0.6 - self.icon_scale) * 30 * dt
        else
            -- Spring back to 1.0 organically when released
            if self.icon_scale < 1 then
                self.icon_scale = self.icon_scale + (1 - self.icon_scale) * 15 * dt
                if self.icon_scale > 0.99 then self.icon_scale = 1 end
            end
        end

        -- Buoyancy: Floating effect
        if self.buoyant then
            -- Use X position to stagger the waves
            local stagger = (self.x or 0) * 0.05
            self.buoyancy_y = math.sin(love.timer.getTime() * 2.5 + stagger) * 2
        else
            self.buoyancy_y = 0
        end
    end,
    onClick = function(self)
        if self.disabled then return end
        self.ripple_r = 0
        self.ripple_a = 0.25
        if props.onClick then props.onClick() end
    end,
    draw = function(self)
      if not self.visible then return end

      love.graphics.push()
      love.graphics.translate(0, self.buoyancy_y or 0)
      love.graphics.setFont(self.font)

      -- Draw the icon on the left if icon is provided
      if self.icon then
        love.graphics.push()
        self.icon_scale = self.icon_scale or 1
        
        -- Translate to icon center to scale locally, then draw icon, then restore matrix
        local cx = self.x + iconSize / 2
        local cy = self.y + self.height / 2
        love.graphics.translate(cx, cy)
        love.graphics.scale(self.icon_scale, self.icon_scale)
        love.graphics.translate(-cx, -cy)

        local leftIcon = icon {
          name = self.icon,
          x = self.x,
          y = self.y + (self.height - iconSize) / 2,
          size = iconSize
        }
        leftIcon:draw()
        
        love.graphics.pop()
      end

      -- Calculate the position of the text based on the presence of an icon
      local textX = self.x
      if self.icon then
        textX = textX + iconSize + padding
      end

      -- Draw the label text
      local c = color or configs.theme:read_color("label", "LABEL_TEXT", "#dfe6e9")
      love.graphics.setColor(c)
      local txt = (self.get_text and self.get_text()) or self.text or ""
      
      local available_width = nil
      if self.max_width then
        available_width = self.max_width - (self.icon and (iconSize + padding) or 0)
      end
      
      local content_w = self.font:getWidth(txt)
      if available_width and content_w > available_width then
        local scroll_speed = 40
        local t = love.timer.getTime()
        local extra = content_w - available_width + 10
        local wait_time = 1.5
        local cycle = wait_time * 2 + (extra / scroll_speed)
        local phase = t % cycle
        local offset = 0
        
        if phase < wait_time then
            offset = 0
        elseif phase < wait_time + (extra / scroll_speed) then
            offset = (phase - wait_time) * scroll_speed
        else
            offset = extra
        end
        
        -- Store current scissor state
        local sx, sy, sw, sh = love.graphics.getScissor()
        
        local tx1, ty1 = love.graphics.transformPoint(textX, self.y)
        local tx2, ty2 = love.graphics.transformPoint(textX + available_width, self.y + self.height)
        local nx, ny = math.min(tx1, tx2), math.min(ty1, ty2)
        local nw, nh = math.abs(tx2 - tx1), math.abs(ty2 - ty1)
        
        -- Apply intersected scissor
        if sx then
            local ix = math.max(sx, nx)
            local iy = math.max(sy, ny)
            local ir = math.min(sx + sw, nx + nw)
            local ib = math.min(sy + sh, ny + nh)
            if ir > ix and ib > iy then
                love.graphics.setScissor(ix, iy, ir - ix, ib - iy)
            else
                love.graphics.setScissor(nx, ny, 0, 0)
            end
        else
            love.graphics.setScissor(nx, ny, nw, nh)
        end
        
        love.graphics.print(txt, textX - offset, self.y)
        
        -- Restore original scissor
        if sx then
            love.graphics.setScissor(sx, sy, sw, sh)
        else
            love.graphics.setScissor()
        end
      else
        love.graphics.print(txt, textX, self.y)
      end

      love.graphics.setColor({ 1, 1, 1 }) -- Reset color to white

      -- Liquid UI: Ripple (for footer/icon feedback)
      if self.ripple_a and self.ripple_a > 0 then
          love.graphics.setColor(c[1], c[2], c[3], self.ripple_a)
          love.graphics.setLineWidth(1)
          
          local txt = (self.get_text and self.get_text()) or self.text or ""
          local tw = self.font:getWidth(txt)
          local content_w = (self.icon and (iconSize + padding) or 0) + tw
          local icx = self.x + content_w / 2
          local icy = self.y + self.height / 2
          love.graphics.circle("line", icx, icy, self.ripple_r)
      end

      love.graphics.pop()
    end,
  }
end

return label
