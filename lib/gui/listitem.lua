local component = require('lib.gui.badr')
local utils = require('helpers.utils')

return function(props)
  local font = props.font or love.graphics.getFont()
  local padding = {
    horizontal = (props.leftPadding or 4) + (props.rightPadding or 4),
    vertical = (props.topPadding or 8) + (props.bottomPadding or 8)
  }
  local text = props.text or ""
  local t = love.graphics.newText(font, text)
  local labelWidth, labelHeight = t:getWidth(), t:getHeight()

  local itemHeight = props.itemHeight or 16
  local width = math.max(props.width or 0, padding.horizontal + labelWidth)
  local height = math.max(props.height or 0, itemHeight + padding.vertical)

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
    disabled = props.disabled or false,
    active = props.active or false,
    -- Colors and styles
    backgroundColor = props.backgroundColor or utils.hex '#000000',
    hoverColor = props.hoverColor or utils.hex '#636e72',
    textColor = props.textColor or utils.hex '#dfe6e9',
    focusColor = props.focusColor or utils.hex '#2d3436',
    checkColor = props.checkColor or utils.hex '#ffffff',
    borderWidth = props.borderWidth or 2,
    -- Focus state
    last_focused = false,
    -- Events
    onFocus = props.onFocus,
    onClick = props.onClick,
    -- Key press handling for toggling checkbox with Enter/Return key
    onKeyPress = function(self, key)
      if key == "return" and self.focused and not self.disabled then
        if self.onClick then self:onClick() end
      end
    end,
    update = function(self)
      if self.focused and not self.last_focused then
        if self.onFocus then self:onFocus() end
      end
      self.last_focused = self.focused
    end,
    draw = function(self)
      if not self.visible then return end
      love.graphics.push()
      love.graphics.setFont(font)

      -- Background and focus styling
      if self.focused or self.active then
        love.graphics.setColor(self.focusColor)
        love.graphics.rectangle("fill", self.x, self.y, self.parent.width or self.width, self.height)
      end

      if self.active then
        love.graphics.setColor(self.textColor)
        love.graphics.rectangle("fill", self.x, self.y, 4, self.height)
      end

      -- Inner box for the checkbox background
      love.graphics.setColor(self.hoverColor)

      -- Checkbox mark if checked
      if self.checked then
        love.graphics.setColor(self.checkColor)
      end

      -- Draw the label next to the checkbox
      love.graphics.setColor(self.textColor)
      love.graphics.draw(t, self.x + padding.horizontal, self.y + height / 2 - labelHeight / 2)

      love.graphics.pop()
    end
  }
end
