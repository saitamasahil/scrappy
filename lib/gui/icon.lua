local component = require 'lib.gui.badr'

-- Icons table
local icons = {
  caret_left = love.graphics.newImage("assets/icons/caret-left-solid.png"),
  caret_right = love.graphics.newImage("assets/icons/caret-right-solid.png"),
  folder = love.graphics.newImage("assets/icons/folder-open-regular.png"),
  display = love.graphics.newImage("assets/icons/display-solid.png"),
  canvas = love.graphics.newImage("assets/icons/object-group-solid.png"),
  image = love.graphics.newImage("assets/icons/image-regular.png"),
  controller = love.graphics.newImage("assets/icons/gamepad-solid.png"),
  warn = love.graphics.newImage("assets/icons/triangle-exclamation-solid.png"),
  info = love.graphics.newImage("assets/icons/circle-info-solid.png"),
  cd = love.graphics.newImage("assets/icons/compact-disc-solid.png"),
  square = love.graphics.newImage("assets/icons/square-regular.png"),
  suqare_check = love.graphics.newImage("assets/icons/square-check-solid.png"),
  button_a = love.graphics.newImage("assets/inputs/switch_button_a.png"),
  button_b = love.graphics.newImage("assets/inputs/switch_button_b.png"),
  button_x = love.graphics.newImage("assets/inputs/switch_button_x.png"),
  button_y = love.graphics.newImage("assets/inputs/switch_button_y.png"),
  dpad = love.graphics.newImage("assets/inputs/switch_dpad_vertical_outline.png"),
  select = love.graphics.newImage("assets/inputs/switch_button_sl.png"),
}

return function(props)
  local name = props.name
  local icon = icons[name]

  if not icon then
    icon = icons["warn"]
  end

  local boxSize = props.size or 24
  local iconWidth, iconHeight = icon:getWidth(), icon:getHeight()
  local sx, sy = boxSize / iconWidth, boxSize / iconHeight

  -- Calculate the position to center the icon within the box
  local offsetX = (boxSize - iconWidth * sx) / 2
  local offsetY = (boxSize - iconHeight * sy) / 2

  return component {
    id = props.id or tostring(love.timer.getTime()),
    x = props.x or 0,
    y = props.y or 0,
    width = boxSize,
    height = boxSize,
    focusable = false,
    draw = function(self)
      love.graphics.push()

      -- Draw transparent box as the icon background
      love.graphics.setColor(1, 1, 1, 0) -- Fully transparent background
      love.graphics.rectangle("fill", self.x, self.y, self.width, self.height)

      -- Draw the icon centered within the box
      love.graphics.setColor(1, 1, 1, 1) -- Reset color to opaque for the icon
      love.graphics.draw(icon, self.x + offsetX, self.y + offsetY, 0, sx, sy)

      love.graphics.pop()
    end,
  }
end
