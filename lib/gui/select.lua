local component = require("lib.gui.badr")
local icon      = require("lib.gui.icon")
local theme     = require("helpers.config").theme

return function(props)
  local font = props.font or love.graphics.getFont()
  local padding = {
    horizontal = (props.leftPadding or 4) + (props.rightPadding or 4),
    vertical = (props.topPadding or 4) + (props.bottomPadding or 4)
  }
  local options = props.options or {}
  local currentIndex = props.startIndex or 1

  -- Calculate width and height based on the longest option text
  local maxTextWidth = 0
  for _, option in ipairs(options) do
    maxTextWidth = math.max(maxTextWidth, font:getWidth(option))
  end

  local iconSize = 16 -- Define the size of the icons
  local width = props.width or 0
  local height = math.max(props.height or 0, font:getHeight() + padding.vertical)

  -- Scroll-related variables
  local contentWidth = width - 2 * iconSize - padding.horizontal
  local scrollOffset = 0
  local scrollSpeed = 50 -- Pixels per second
  local spacer = " • " -- Spacer between wrapped text
  local spacerWidth = font:getWidth(spacer) -- Width of the spacer

  return component {
    options = options,
    currentIndex = currentIndex,
    x = props.x or 0,
    y = props.y or 0,
    width = width,
    height = height,
    font = font,
    focusable = props.focusable or true,
    -- styles
    -- styles (explicit overrides only)
    backgroundColor = props.backgroundColor,
    focusColor = props.focusColor,
    textColor = props.textColor,
    leftPadding = props.leftPadding or 4,
    rightPadding = props.rightPadding or 4,
    topPadding = props.topPadding or 4,
    bottomPadding = props.bottomPadding or 4,
    -- logic
    onKeyPress = function(self, key)
      if key == "left" then
        self.currentIndex = self.currentIndex > 1 and self.currentIndex - 1 or #self.options
        if props.onChange then props.onChange(key, self.currentIndex) end
      elseif key == "right" then
        self.currentIndex = self.currentIndex < #self.options and self.currentIndex + 1 or 1
        if props.onChange then props.onChange(key, self.currentIndex) end
      end
    end,
    onFocus = props.onFocus,
    last_focused = false,
    onUpdate = function(self, dt)
      if self.focused and not self.last_focused then
        if self.onFocus then self:onFocus() end
      end
      self.last_focused = self.focused

      self.anim_p = self.anim_p or (self.focused and 1 or 0)
      local target_p = self.focused and 1 or 0
      self.anim_p = self.anim_p + (target_p - self.anim_p) * 15 * dt

      -- Update scroll offset if text is wider than the button
      local textWidth = font:getWidth(self.options[self.currentIndex] or "")
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

      -- Scale bump on focus
      local cx, cy = self.x + self.width/2, self.y + self.height/2
      local scale = 1.0 + (self.anim_p or 0) * 0.02
      love.graphics.translate(cx, cy)
      love.graphics.scale(scale, scale)
      love.graphics.translate(-cx, -cy)

      love.graphics.setFont(font)

      -- Resolve colors dynamically
      local backgroundColor = self.backgroundColor or theme:read_color("select", "SELECT_BACKGROUND", "#2d3436")
      local focusColor = self.focusColor or theme:read_color("select", "SELECT_FOCUS", "#636e72")
      local textColor = self.textColor or theme:read_color("select", "SELECT_TEXT", "#dfe6e9")

      -- Interpolate colors
      local anim_p = self.anim_p or 0
      local br = backgroundColor[1] + (focusColor[1] - backgroundColor[1]) * anim_p
      local bg = backgroundColor[2] + (focusColor[2] - backgroundColor[2]) * anim_p
      local bb = backgroundColor[3] + (focusColor[3] - backgroundColor[3]) * anim_p
      local ba = (backgroundColor[4] or 1) + ((focusColor[4] or 1) - (backgroundColor[4] or 1)) * anim_p
      love.graphics.setColor(br, bg, bb, ba)

      -- Draw background rectangle
      love.graphics.rectangle('fill', self.x, self.y, self.width, self.height)

      -- Draw caret icons using the icon component
      local leftIcon = icon {
        name = "caret_left",
        x = self.x + self.leftPadding,
        y = self.y + (self.height - iconSize) * 0.5,
        size = iconSize
      }
      local rightIcon = icon {
        name = "caret_right",
        x = self.x + self.width - iconSize - self.rightPadding,
        y = self.y + (self.height - iconSize) * 0.5,
        size = iconSize
      }

      leftIcon:draw()  -- Draw the left caret
      rightIcon:draw() -- Draw the right caret


      local contentX = self.x + iconSize + self.leftPadding * 0.5
      local prevScissorX, prevScissorY, prevScissorW, prevScissorH = love.graphics.getScissor()
      local clipX1, clipY1 = love.graphics.transformPoint(contentX, self.y)
      local clipX2, clipY2 = love.graphics.transformPoint(contentX + contentWidth, self.y + self.height)
      local clipX = math.min(clipX1, clipX2)
      local clipY = math.min(clipY1, clipY2)
      local clipW = math.abs(clipX2 - clipX1)
      local clipH = math.abs(clipY2 - clipY1)
      local targetX, targetY, targetW, targetH = clipX, clipY, clipW, clipH
      if prevScissorX then
        local prevRight = prevScissorX + prevScissorW
        local prevBottom = prevScissorY + prevScissorH
        local clipRight = clipX + clipW
        local clipBottom = clipY + clipH
        targetX = math.max(prevScissorX, clipX)
        targetY = math.max(prevScissorY, clipY)
        targetW = math.min(prevRight, clipRight) - targetX
        targetH = math.min(prevBottom, clipBottom) - targetY
      end
      local appliedScissor = false
      local skipText = false
      if targetW > 0 and targetH > 0 then
        love.graphics.setScissor(targetX, targetY, targetW, targetH)
        appliedScissor = true
      else
        skipText = true
      end

      -- Draw the current option text, centered between the icons
      local currentOption = self.options[self.currentIndex] or ""
      local textY = self.y + self.height * 0.5 - font:getHeight() * 0.5

      love.graphics.setColor(textColor)

      local textWidth = font:getWidth(currentOption)

      if not skipText then
        if textWidth <= contentWidth then
          -- Center the text if it fits within the button
          love.graphics.printf(currentOption, contentX, textY, contentWidth, 'center')
        else
          -- Scroll the text if it's longer than the button width
          local textX = contentX - scrollOffset
          love.graphics.print(currentOption, textX, self.y + self.topPadding)

          -- Draw the wrapped text with a spacer to the right of the first text
          if scrollOffset > textWidth - (contentWidth) then
            love.graphics.print(spacer .. currentOption, textX + textWidth, self.y + self.topPadding)
          end
        end
      end

      if appliedScissor then
        if prevScissorX then
          love.graphics.setScissor(prevScissorX, prevScissorY, prevScissorW, prevScissorH)
        else
          love.graphics.setScissor()
        end
      end
      love.graphics.pop()
    end
  }
end
