local component = require("lib.gui.badr")
local label     = require("lib.gui.label")
local configs   = require("helpers.config")

local function popup(props)
  local theme = configs.theme
  local backgroundColor = theme:read_color("popup", "POPUP_BACKGROUND", "#000000")
  local opacity = theme:read_number("popup", "POPUP_OPACITY", 0.75)
  local boxColor = theme:read_color("popup", "POPUP_BOX", "#2d3436")
  local textColor = theme:read_color("label", "LABEL_TEXT", "#dfe6e9")
  backgroundColor[4] = opacity

  return component {
    title = props.title or "Info",
    content = props.content or "Info content",
    visible = props.visible,
    id = props.id,
    x = props.x or 0,
    y = props.y or 0,
    width = props.width or love.graphics.getWidth(),
    height = props.height or love.graphics.getHeight(),
    padding = props.padding or (10 * (_G.scale or 1)),
    _font = props.font or love.graphics.getFont(),
    draw = function(self)
      if not self.visible then 
        self.fade = 0
        return 
      end

      -- Use live screen dimensions so popups adapt to current window size
      local screenWidth = love.graphics.getWidth()
      local screenHeight = love.graphics.getHeight()

      -- Organic damping animation (Increased to 20 for snappier feel)
      self.fade = (self.fade or 0) + (1 - (self.fade or 0)) * 20 * love.timer.getDelta()
      if self.fade > 0.999 then self.fade = 1 end

      love.graphics.push()
      love.graphics.origin()

      local content_width, content_height, wrappedText
      local margin = 20 * (_G.scale or 1)

      if #self.children > 0 then
        content_width = math.min(self.children[1].width + self.padding * 2, screenWidth - margin)
        content_height = math.min(self.children[1].height + self.padding * 2, screenHeight)
      else
        content_width = math.min(self.width, screenWidth - margin)
        _, wrappedText = self._font:getWrap(self.content, content_width - (20 * (_G.scale or 1)))
        content_height = self._font:getHeight() * #wrappedText + (20 * (_G.scale or 1))
      end

      local center_width = (screenWidth - content_width) / 2
      local center_height = (screenHeight - content_height) / 2

      -- Background Overlay
      local overlayBG = theme:read_color("popup", "POPUP_BACKGROUND", "#000000")
      local overlayOpacity = theme:read_number("popup", "POPUP_OPACITY", 0.75)
      overlayBG[4] = overlayOpacity * self.fade
      love.graphics.setColor(overlayBG)
      love.graphics.rectangle("fill", 0, 0, screenWidth, screenHeight)

      local popup_scale = 0.85 + 0.15 * self.fade
      local sx = screenWidth / 2
      local sy = screenHeight / 2
      love.graphics.translate(sx, sy)
      love.graphics.scale(popup_scale, popup_scale)
      love.graphics.translate(-sx, -sy)

      local overlayLabel = label {
        text = self.title,
        icon = props.icon or "info",
        font = self._font,
        x = center_width,
        y = center_height - (30 * (_G.scale or 1)),
      }
      overlayLabel:draw()

      -- If the popup has a child, draw it
      if #self.children > 0 then
        local child = self.children[1]

        love.graphics.push()
        love.graphics.translate(center_width, center_height)
        local boxColor = configs.theme:read_color("popup", "POPUP_BOX", "#2d3436")
        love.graphics.setColor(boxColor)
        love.graphics.rectangle("fill", 0, 0, content_width, content_height)

        -- Clip child rendering to the popup box using scissor in screen coordinates
        local bx1, by1 = love.graphics.transformPoint(0, 0)
        local bx2, by2 = love.graphics.transformPoint(content_width, content_height)
        local clip_x = math.min(bx1, bx2)
        local clip_y = math.min(by1, by2)
        local clip_w = math.abs(bx2 - bx1)
        local clip_h = math.abs(by2 - by1)
        love.graphics.setScissor(clip_x, clip_y, clip_w, clip_h)

        local textColor = configs.theme:read_color("label", "LABEL_TEXT", "#dfe6e9")
        love.graphics.setColor(textColor)
        love.graphics.translate(self.padding, self.padding)
        child:draw()

        love.graphics.setScissor()
        love.graphics.pop()
      else
        local _, wrappedtext = self._font:getWrap(self.content, content_width - (20 * (_G.scale or 1)))
        love.graphics.push()
        love.graphics.translate(center_width, center_height)
        local boxColor = configs.theme:read_color("popup", "POPUP_BOX", "#2d3436")
        love.graphics.setColor(boxColor)
        love.graphics.rectangle("fill", 0, 0, content_width, content_height)
        local textColor = configs.theme:read_color("label", "LABEL_TEXT", "#dfe6e9")
        love.graphics.setColor(textColor)
        love.graphics.printf(wrappedtext, 10 * (_G.scale or 1), 5 * (_G.scale or 1), content_width - (20 * (_G.scale or 1)), "left")
        love.graphics.pop()
      end

      love.graphics.pop()
    end,
  }
end

return popup
