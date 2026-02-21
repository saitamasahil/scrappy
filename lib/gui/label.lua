local component = require("lib.gui.badr")
local icon      = require("lib.gui.icon")
local configs   = require("helpers.config")

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
    draw = function(self)
      if not self.visible then return end

      love.graphics.push()
      love.graphics.setFont(self.font)

      -- Draw the icon on the left if icon is provided
      if self.icon then
        local leftIcon = icon {
          name = self.icon,
          x = self.x,
          y = self.y + (self.height - iconSize) / 2,
          size = iconSize
        }
        leftIcon:draw()
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
      love.graphics.pop()
    end,
  }
end

return label
