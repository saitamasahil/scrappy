local component = require("lib.gui.badr")
local theme     = require("helpers.config").theme

return function(props)
  local font = props.font or love.graphics.getFont()
  local padding = {
    horizontal = (props.leftPadding or 4) + (props.rightPadding or 4),
    vertical = (props.topPadding or 4) + (props.bottomPadding or 4)
  }
  local width = math.max(props.width or 0, font:getWidth(props.text) + padding.horizontal)
  local height = math.max(props.height or 0, font:getHeight() + padding.vertical)

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
    backgroundColor = theme:read_color("button", "BUTTON_BACKGROUND", "#2d3436"),
    focusColor = theme:read_color("button", "BUTTON_FOCUS", "#636e72"),
    textColor = theme:read_color("button", "BUTTON_TEXT", "#dfe6e9"),
    leftPadding = props.leftPadding or 4,
    rightPadding = props.rightPadding or 4,
    topPadding = props.topPadding or 4,
    bottomPadding = props.bottomPadding or 4,
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
      -- Set color based on focus
      if self.focused then
        love.graphics.setColor(self.focusColor)
      else
        love.graphics.setColor(self.backgroundColor)
      end

      -- Draw button background
      love.graphics.rectangle('fill', self.x, self.y, self.width, self.height, self.cornerRadius)

      -- Draw button text
      love.graphics.setColor(self.textColor)
      love.graphics.printf(self.text, self.x + self.leftPadding, self.y + self.topPadding,
        self.width - padding.horizontal, 'center')

      -- Reset color
      love.graphics.setColor({ 1, 1, 1 })
      love.graphics.pop()
    end
  }
end
