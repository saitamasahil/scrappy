local component = require('lib.gui.badr')
local icon = require('lib.gui.icon')
local utils = require('helpers.utils')

return function(props)
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
    focusable = props.focusable or true,
    -- Colors and styles
    backgroundColor = props.backgroundColor or utils.hex '#000000',
    hoverColor = props.hoverColor or utils.hex '#636e72',
    textColor = props.textColor or utils.hex '#dfe6e9',
    focusColor = props.focusColor or utils.hex '#2d3436',
    checkColor = props.checkColor or utils.hex '#ffffff',
    borderWidth = props.borderWidth or 2,
    -- Events
    onToggle = props.onToggle,
    -- Key press handling for toggling checkbox with Enter/Return key
    onKeyPress = function(self, key)
      if key == "return" and self.focused then
        self.checked = not self.checked
        if self.onToggle then self:onToggle(self.checked) end
      end
    end,
    draw = function(self)
      if not self.visible then return end
      love.graphics.push()
      love.graphics.setFont(font)

      -- Background and focus styling
      if self.focused then
        love.graphics.setColor(self.focused and self.focusColor or self.backgroundColor)
        love.graphics.rectangle("fill", self.x, self.y, self.parent.width or self.width, self.height)
      end

      local bgIcon = icon {
        name = "square",
        x = self.x + padding.horizontal / 2,
        y = self.y + padding.vertical / 2,
        size = checkboxSize
      }

      local fgIcon = icon {
        name = "square_check",
        x = self.x + padding.horizontal / 2,
        y = self.y + padding.vertical / 2,
        size = checkboxSize
      }

      -- Inner box for the checkbox background
      love.graphics.setColor(self.hoverColor)
      bgIcon:draw()

      -- Checkbox mark if checked
      if self.checked then
        love.graphics.setColor(self.checkColor)
        fgIcon:draw()
      end

      -- Draw the label next to the checkbox
      love.graphics.setColor(self.textColor)
      love.graphics.draw(t, self.x + checkboxSize + padding.horizontal, self.y + height / 2 - labelHeight / 2)

      love.graphics.pop()
    end
  }
end
