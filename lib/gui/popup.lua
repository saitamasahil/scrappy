local component = require("lib.gui.badr")
local label     = require("lib.gui.label")
local theme     = require("helpers.config").theme

local function popup(props)
  local backgroundColor = theme:read_color("popup", "POPUP_BACKGROUND", "#000000")
  local opacity = theme:read_number("popup", "POPUP_OPACITY", 0.75)
  local boxColor = theme:read_color("popup", "POPUP_BOX", "#2d3436")
  backgroundColor[4] = opacity

  local screenWidth = love.graphics.getWidth()
  local screenHeight = love.graphics.getHeight()
  return component {
    title = props.title or "Info",
    content = props.content or "Info content",
    visible = props.visible,
    id = props.id,
    x = props.x or 0,
    y = props.y or 0,
    width = screenWidth,
    height = screenHeight,
    _font = props.font or love.graphics.getFont(),
    draw = function(self)
      if not self.visible then return end

      local content_width = self.width - 150
      local _, wrappedText = self._font:getWrap(self.content, content_width)
      local content_height = self._font:getHeight() * #wrappedText

      local center_width, center_height = screenWidth * 0.5 - content_width * 0.5,
          screenHeight * 0.5 - content_height * 0.5

      local overlayLabel = label {
        text = self.title,
        icon = props.icon or "info",
        font = self._font,
        x = self.x + center_width,
        y = self.y + center_height - 30,
      }

      local infoTextComponent = component {
        text = self.content,
        font = props.font or love.graphics.getFont(),
        width = content_width,
        height = 30,
        draw = function(self)
          local _, wrappedtext = self.font:getWrap(self.text, self.width - 10)
          love.graphics.push()
          love.graphics.translate(center_width, center_height)
          love.graphics.setColor(boxColor)
          love.graphics.rectangle("fill", self.x, self.y, self.width, #wrappedtext * self.height + 10)
          love.graphics.setColor(1, 1, 1)
          love.graphics.printf(wrappedtext, self.x + 10, self.y + 5, self.width - 10, "left")
          love.graphics.pop()
        end
      }

      -- Background
      love.graphics.push()
      love.graphics.setColor(backgroundColor)
      love.graphics.rectangle("fill", 0, 0, screenWidth, screenHeight)
      love.graphics.pop()

      overlayLabel:draw()
      infoTextComponent:draw()
    end,
  }
end

return popup
