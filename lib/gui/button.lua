local component = require("lib.gui.badr")
local icon      = require("lib.gui.icon")
local theme     = require("helpers.config").theme

return function(props)
  local font = props.font or love.graphics.getFont()
  local padding = {
    horizontal = (props.leftPadding or 4) + (props.rightPadding or 4),
    vertical = (props.topPadding or 4) + (props.bottomPadding or 4)
  }
  -- local width = math.max(props.width or 0, font:getWidth(props.text) + padding.horizontal)
  local width = props.width or 0
  local height = math.max(props.height or 0, font:getHeight() + padding.vertical)

  local iconSize = props.iconSize or 16

  -- Scroll-related variables
  local scrollOffset = 0
  local scrollSpeed = 50 -- Pixels per second
  local spacer = " • " -- Spacer between wrapped text
  local spacerWidth = font:getWidth(spacer) -- Width of the spacer

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
    leftPadding = props.leftPadding or 8,
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
    onUpdate = function(self, dt)
      -- Update scroll offset if text is wider than the button
      local textWidth = font:getWidth(self.text)
      -- Only scroll if the button is focused and the text is longer than the button width
      if self.focused and textWidth > self.width - padding.horizontal then
        scrollOffset = scrollOffset + scrollSpeed * dt
        -- Wrap the scroll offset when it exceeds the text width
        if scrollOffset > textWidth + spacerWidth then
          scrollOffset = 0 -- Reset to the beginning
        end
      else
        scrollOffset = 0 -- Reset scroll offset when not focused
      end
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

      if self.icon then
        local leftIcon = icon {
          name = self.icon,
          x = self.x + self.leftPadding,
          y = self.y + (self.height - iconSize) * 0.5,
          size = iconSize
        }
        leftIcon:draw()
      end

      -- Draw button text
      love.graphics.setColor(self.textColor)
      love.graphics.setScissor(self.x, self.y, self.width, self.height) -- Clip text to button bounds

      local textWidth = font:getWidth(self.text)

      if textWidth <= self.width - padding.horizontal then
        -- Center the text if it fits within the button
        love.graphics.printf(self.text, self.x, self.y + self.topPadding, self.width, 'center')
      else
        -- Scroll the text if it's longer than the button width
        local textX = self.x + self.leftPadding - scrollOffset
        love.graphics.print(self.text, textX, self.y + self.topPadding)

        -- Draw the wrapped text with a spacer to the right of the first text
        if scrollOffset > textWidth - (self.width - padding.horizontal) then
          love.graphics.print(spacer .. self.text, textX + textWidth, self.y + self.topPadding)
        end
      end

      love.graphics.setScissor() -- Reset scissor
      love.graphics.pop()
    end
  }
end
