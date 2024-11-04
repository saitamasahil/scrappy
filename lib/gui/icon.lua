local component = require 'lib.gui.badr'

-- Icons table
local icons = {
  chevron_left = love.graphics.newImage("assets/icons/Chevron-Arrow-Left.png"),
  chevron_right = love.graphics.newImage("assets/icons/Chevron-Arrow-Right.png"),
  gear = love.graphics.newImage("assets/icons/Gear.png"),
  folder = love.graphics.newImage("assets/icons/Folder.png"),
  redo = love.graphics.newImage("assets/icons/Redo.png"),
  disk = love.graphics.newImage("assets/icons/Disk.png"),
  folder_image = love.graphics.newImage("assets/icons/Folder-Image.png"),
  file_image = love.graphics.newImage("assets/icons/File-Image.png"),
  controller = love.graphics.newImage("assets/icons/Game-Controller.png"),
  clock = love.graphics.newImage("assets/icons/Clock.png"),
  warn = love.graphics.newImage("assets/icons/Exclamation-Mark.png"),
  info = love.graphics.newImage("assets/icons/Info.png"),
  cd = love.graphics.newImage("assets/icons/CD.png"),
  play = love.graphics.newImage("assets/icons/Play.png"),
  at = love.graphics.newImage("assets/icons/Asperand-Sign.png"),
  left_arrow = love.graphics.newImage("assets/icons/Left-Arrow.png"),
  cursor = love.graphics.newImage("assets/icons/Cursor-3.png")
}

return function(props)
  local name = props.name
  local icon = icons[name]

  if not icon then
    icon = icons["warn"]
  end

  local boxSize = props.size or 16 -- Default box size of 16x16
  local iconWidth, iconHeight = icon:getWidth(), icon:getHeight()

  -- Calculate the position to center the icon within the box
  local offsetX = (boxSize - iconWidth) / 2
  local offsetY = (boxSize - iconHeight) / 2

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
      love.graphics.draw(icon, self.x + offsetX, self.y + offsetY)

      love.graphics.pop()
    end,
  }
end
