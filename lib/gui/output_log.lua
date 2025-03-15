local component = require("lib.gui.badr")

return function(props)
  local font = props.font or love.graphics.getFont()
  local padding = props.padding or 10

  local width = props.width or 0
  local height = props.height or 0

  return component {
    id = props.id or tostring(love.timer.getTime()),
    width = width - 4 * padding,
    height = height,
    font = font,
    text = "",
    draw = function(self)
      love.graphics.push()
      love.graphics.setColor(0, 0, 0, 0.5)
      love.graphics.rectangle("fill", self.x, self.y, self.width, self.height)
      love.graphics.setColor(1, 1, 1)
      love.graphics.stencil(function()
        love.graphics.rectangle("fill", self.x, self.y, self.width, self.height)
      end, "replace", 1)
      love.graphics.setStencilTest("greater", 0)

      -- Split the text into lines
      local lines = {}
      for s in self.text:gmatch("[^\r\n]+") do
        table.insert(lines, s)
      end

      -- Calculate the total height of all the lines
      local totalTextHeight = #lines * self.font:getHeight()

      -- Draw text from bottom-up
      local offset = self.height - totalTextHeight
      for i = 1, #lines do
        love.graphics.print(lines[i], self.x + 10, self.y + offset)
        offset = offset + self.font:getHeight()
      end

      love.graphics.setStencilTest()
      love.graphics.pop()
    end
  }
end
