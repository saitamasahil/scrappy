local component = require 'lib.gui.badr'

-- https://github.com/s-walrus/hex2color/blob/master/hex2color.lua
local function Hex(hex, value)
  return {
    tonumber(string.sub(hex, 2, 3), 16) / 256,
    tonumber(string.sub(hex, 4, 5), 16) / 256,
    tonumber(string.sub(hex, 6, 7), 16) / 256,
    value or 1 }
end

return function(props)
  local font = props.font or love.graphics.getFont()
  local padding = {
    horizontal = (props.leftPadding or 12) + (props.rightPadding or 12),
    vertical = (props.topPadding or 8) + (props.bottomPadding or 8)
  }
  local width = math.max(props.width or 0, font:getWidth(props.text) + padding.horizontal)
  local height = math.max(props.height or 0, font:getHeight(props.text) + padding.vertical)

  return component {
    text = props.text,
    icon = props.icon or nil,
    --
    id = props.id or tostring(love.timer.getTime()),
    x = props.x or 0,
    y = props.y or 0,
    width = width,
    height = height,
    font = font,
    focusable = props.focusable or true,
    -- styles
    opacity = props.opacity or 1,
    backgroundColor = props.backgroundColor or Hex '#2d3436',
    hoverColor = props.hoverColor or Hex '#636e72',
    textColor = props.textColor or Hex '#dfe6e9',
    cornerRadius = props.cornerRadius or 0,
    leftPadding = props.leftPadding or 12,
    rightPadding = props.rightPadding or 12,
    topPadding = props.topPadding or 8,
    bottomPadding = props.bottomPadding or 8,
    borderColor = props.borderColor or { 1, 1, 1 },
    borderWidth = props.borderWidth or 0,
    border = props.border or false,
    -- logic
    onClick = props.onClick,
    disabled = props.disabled or false,
    onKeyPress = function(self, key)
      if key == "return" and self.focused and props.onClick then
        props.onClick()
      end
    end,
    onUpdate = function(self)
    end,
    --
    draw = function(self)
      if not self.visible then return end
      love.graphics.push()
      love.graphics.setFont(font)
      -- border
      if self.border then
        love.graphics.setColor(self.borderColor)
        love.graphics.setLineWidth(self.borderWidth)
        love.graphics.rectangle('line', self.x, self.y, self.width, self.height, self.cornerRadius)
        love.graphics.setColor({ 0, 0, 0 })
      end

      -- Set color based on focus
      if self.focused then
        love.graphics.setColor(self.hoverColor[1], self.hoverColor[2], self.hoverColor[3], self.opacity)
      else
        love.graphics.setColor(self.backgroundColor[1], self.backgroundColor[2], self.backgroundColor[3], self.opacity)
      end

      -- Draw button background
      love.graphics.rectangle('fill', self.x, self.y, self.width, self.height, self.cornerRadius)

      -- Draw button text
      love.graphics.setColor(self.textColor[1], self.textColor[2], self.textColor[3], self.opacity)
      love.graphics.printf(self.text, self.x + self.leftPadding, self.y + self.topPadding,
        self.width - padding.horizontal, 'center')

      -- Reset color
      love.graphics.setColor({ 1, 1, 1 })
      love.graphics.pop()
    end
  }
end
