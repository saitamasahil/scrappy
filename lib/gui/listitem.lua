local component = require('lib.gui.badr')
local icon      = require("lib.gui.icon")
local configs   = require('helpers.config')

return function(props)
  local theme = configs.theme
  local font = props.font or love.graphics.getFont()
  local padding = {
    horizontal = (props.leftPadding or 4) + (props.rightPadding or 4),
    vertical = (props.topPadding or 8) + (props.bottomPadding or 8)
  }
  local iconSize = props.icon and 16 or 0
  local text = props.text or ""

  local itemHeight = theme:read_number("listitem", "ITEM_HEIGHT", 16)
  local height = math.max(props.height or 0, itemHeight + padding.vertical)

  -- Scroll-related variables
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
    width = props.width or 0,
    height = height,
    focusable = props.focusable or true,
    disabled = props.disabled or false,
    active = props.active or false,
    icon = props.icon or nil,
    -- Colors and styles (explicit overrides only, otherwise dynamic in draw)
    backgroundColor = props.backgroundColor,
    focusColor = props.focusColor,
    indicatorColor = nil, -- Resolved in draw
    textColor = props.textColor,
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
      -- Resolve visible if it's a function
      if type(props.visible) == "function" then
        self.visible = props.visible()
      end

      -- Update width if necessary
      if self.width == 0 then
        self.width = self.parent.width
      end
      -- Update focus state
      if self.focused and not self.last_focused then
        if self.onFocus then self:onFocus() end
      end
      self.last_focused = self.focused

      self.anim_p = self.anim_p or (self.focused and 1 or 0)
      local target_p = self.focused and 1 or 0
      self.anim_p = self.anim_p + (target_p - self.anim_p) * 15 * dt

      -- Resolve text if it's a function
      if type(self.text) == "function" then
        self.displayText = self.text()
      else
        self.displayText = self.text or ""
      end

      local contentWidth = self.width - iconSize - padding.horizontal

      -- Update scroll offset if text is wider than the button
      local textWidth = font:getWidth(self.displayText or "")
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
      
      -- Match the modern scale bump from button.lua
      local cx, cy = self.x + self.width/2, self.y + self.height/2
      local scale = 1.0 + (self.anim_p or 0) * 0.02
      love.graphics.translate(cx, cy)
      love.graphics.scale(scale, scale)
      love.graphics.translate(-cx, -cy)
      
      love.graphics.setFont(font)

      -- Ensure displayText is resolved even if update wasn't called (unlikely but safe)
      local displayText = self.displayText
      if not displayText then
        if type(self.text) == "function" then
            displayText = self.text()
        else
            displayText = self.text or ""
        end
      end

      local labelHeight = font:getHeight(displayText)
      local topPadding = self.height * 0.5 - labelHeight * 0.5
      local leftPadding = (props.leftPadding or 4)

      -- Resolve colors dynamically (fixes caching issue)
      local backgroundColor = self.backgroundColor or theme:read_color("listitem", "ITEM_BACKGROUND", "#000000")
      local focusColor = self.focusColor or theme:read_color("listitem", "ITEM_FOCUS", "#2d3436")
      local textColor = self.textColor or theme:read_color("listitem", "ITEM_TEXT", "#dfe6e9")
      
      local indicators = {
        theme:read_color("listitem", "ITEM_INDICATOR_DEFAULT", "#dfe6e9"),
        theme:read_color("listitem", "ITEM_INDICATOR_SUCCESS", "#2ecc71"),
        theme:read_color("listitem", "ITEM_INDICATOR_ERROR", "#e74c3c"),
      }
      local indicatorColor = indicators[props.indicator or 1]

      -- Background and focus styling
      if (self.anim_p or 0) > 0.01 then
        love.graphics.setColor(focusColor[1], focusColor[2], focusColor[3], (focusColor[4] or 1) * self.anim_p)
        love.graphics.rectangle("fill", self.x, self.y, self.width, self.height)
      end

      -- Draw indicator pill (e.g., green for found, red for missing)
      if props.indicator and props.indicator > 1 then
        love.graphics.setColor(indicatorColor)
        local pillWidth = 4
        local pillHeight = self.height * 0.6
        love.graphics.rectangle("fill", self.x + 2, self.y + (self.height - pillHeight) * 0.5, pillWidth, pillHeight, 2, 2)
      end
      if self.icon then
        local leftIcon = icon {
          name = self.icon,
          x = self.x + leftPadding,
          y = self.y + (self.height - iconSize) * 0.5,
          size = iconSize
        }
        leftIcon:draw()
      end

      -- Stencil needed for framebuffer issues
      love.graphics.stencil(
        function()
          love.graphics.rectangle("fill", self.x + padding.horizontal, self.y, self.width - padding.horizontal,
            self.height)
        end,
        "replace", 1
      )
      love.graphics.setStencilTest("greater", 0)
      love.graphics.setColor(textColor)

      local textX = self.x + 2 * leftPadding + iconSize
      local textWidth = font:getWidth(displayText)

      if textWidth <= self.width - padding.horizontal then
        -- Center the text if it fits within the button
        love.graphics.printf(displayText, textX, self.y + topPadding, self.width, 'left')
      else
        -- Scroll the text if it's longer than the button width
        textX = textX - scrollOffset
        love.graphics.print(displayText, textX, self.y + topPadding)

        -- Draw the wrapped text with a spacer to the right of the first text
        if scrollOffset > textWidth - (self.width - padding.horizontal) then
          love.graphics.print(spacer .. displayText, textX + textWidth, self.y + topPadding)
        end
      end

      love.graphics.setStencilTest()
      love.graphics.pop()
    end
  }
end
