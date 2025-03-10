local component = require('lib.gui.badr')
local icon      = require("lib.gui.icon")
local theme     = require('helpers.config').theme

return function(props)
  local font = props.font or love.graphics.getFont()
  local padding = {
    horizontal = (props.leftPadding or 4) + (props.rightPadding or 4),
    vertical = (props.topPadding or 8) + (props.bottomPadding or 8)
  }
  local iconSize = props.icon and 16 or 0
  local text = props.text or ""

  local itemHeight = theme:read_number("listitem", "ITEM_HEIGHT", 16)
  local width = props.width or 0
  local height = math.max(props.height or 0, itemHeight + padding.vertical)

  -- Scroll-related variables
  local contentWidth = width - iconSize - padding.horizontal
  local scrollOffset = 0
  local scrollSpeed = 50 -- Pixels per second
  local spacer = " • " -- Spacer between wrapped text
  local spacerWidth = font:getWidth(spacer) -- Width of the spacer

  local indicators = {
    theme:read_color("listitem", "ITEM_INDICATOR_DEFAULT", "#dfe6e9"),
    theme:read_color("listitem", "ITEM_INDICATOR_SUCCESS", "#2ecc71"),
    theme:read_color("listitem", "ITEM_INDICATOR_ERROR", "#e74c3c"),
  }

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
    backgroundColor = theme:read_color("listitem", "ITEM_BACKGROUND", "#000000"),
    focusColor = theme:read_color("listitem", "ITEM_FOCUS", "#2d3436"),
    indicatorColor = indicators[props.indicator or 1],
    textColor = theme:read_color("listitem", "ITEM_TEXT", "#dfe6e9"),
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
    onUpdate = function(self, dt)
      if self.focused and not self.last_focused then
        if self.onFocus then self:onFocus() end
      end
      self.last_focused = self.focused

      -- Update scroll offset if text is wider than the button
      local textWidth = font:getWidth(self.text or "")
      -- Only scroll if the button is focused and the text is longer than the button width
      if self.focused and textWidth > contentWidth then
        scrollOffset = scrollOffset + scrollSpeed * dt
        -- Wrap the scroll offset when it exceeds the text width
        if scrollOffset > textWidth + spacerWidth then
          scrollOffset = 0 -- Reset to the beginning
        end
      else
        scrollOffset = 0 -- Reset scroll offset when not focused
      end
    end,
    draw = function(self)
      if not self.visible then return end
      love.graphics.push()
      love.graphics.setFont(font)

      local labelHeight = font:getHeight(self.text)
      local topPadding = self.height * 0.5 - labelHeight * 0.5
      local leftPadding = (props.leftPadding or 4)

      -- Background and focus styling
      if self.focused then
        love.graphics.setColor(self.focusColor)
        love.graphics.rectangle("fill", self.x, self.y, self.parent.width or self.width, self.height)
      end

      if self.active then
        love.graphics.setColor(self.indicatorColor)
        love.graphics.rectangle("fill", self.x, self.y + self.height * 0.25, 4, self.height * 0.5)
      end

      if props.icon then
        local leftIcon = icon {
          name = props.icon,
          x = self.x + leftPadding,
          y = self.y + (self.height - iconSize) * 0.5,
          size = iconSize
        }
        leftIcon:draw()
      end

      -- Stencil needed for framebuffer issues
      love.graphics.stencil(
        function()
          love.graphics.rectangle("fill", self.x + padding.horizontal, self.y,
            (self.parent.width or self.width) - padding.horizontal, self.height)
        end,
        "replace", 1
      )
      love.graphics.setStencilTest("greater", 0)
      love.graphics.setColor(self.textColor)

      local textX = self.x + 2 * leftPadding + iconSize
      local textWidth = font:getWidth(self.text)

      if textWidth <= self.width - padding.horizontal then
        -- Center the text if it fits within the button
        love.graphics.printf(self.text, textX, self.y + topPadding, self.width, 'left')
      else
        -- Scroll the text if it's longer than the button width
        textX = textX - scrollOffset
        love.graphics.print(self.text, textX, self.y + topPadding)

        -- Draw the wrapped text with a spacer to the right of the first text
        if scrollOffset > textWidth - (self.width - padding.horizontal) then
          love.graphics.print(spacer .. self.text, textX + textWidth, self.y + topPadding)
        end
      end

      love.graphics.setStencilTest()
      love.graphics.pop()
    end
  }
end
