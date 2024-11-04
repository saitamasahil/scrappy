local component = require 'lib.gui.badr'

local function label(options)
  local _font = options.font or love.graphics.getFont()
  local color = options.color or { 1, 1, 1 }

  return component {
    text = options.text or options,
    visible = options.visible or true,
    id = options.id,
    --
    width = _font:getWidth(options.text or options),
    height = _font:getHeight(options.text or options),
    onClick = options.onClick or nil,
    font = _font,
    draw = function(self)
      if not self.visible then return end
      love.graphics.setFont(self.font)
      love.graphics.setColor({
        color[1], color[2], color[3], options.opacity
      })
      love.graphics.print(self.text, self.x, self.y)
      love.graphics.setColor({ 1, 1, 1 })
    end,
  }
end

return label
