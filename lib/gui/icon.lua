local component = require 'lib.gui.badr'
local configs = require 'helpers.config'
local theme = configs.theme

-- Icons table
local icons = {
  caret_left   = love.graphics.newImage("assets/icons/caret-left-solid.png"),
  caret_right  = love.graphics.newImage("assets/icons/caret-right-solid.png"),
  folder       = love.graphics.newImage("assets/icons/folder-open-regular.png"),
  display      = love.graphics.newImage("assets/icons/display-solid.png"),
  canvas       = love.graphics.newImage("assets/icons/object-group-solid.png"),
  image        = love.graphics.newImage("assets/icons/image-regular.png"),
  controller   = love.graphics.newImage("assets/icons/gamepad-solid.png"),
  warn         = love.graphics.newImage("assets/icons/triangle-exclamation-solid.png"),
  info         = love.graphics.newImage("assets/icons/circle-info-solid.png"),
  cd           = love.graphics.newImage("assets/icons/compact-disc-solid.png"),
  square       = love.graphics.newImage("assets/icons/square-regular.png"),
  square_check = love.graphics.newImage("assets/icons/square-check-solid.png"),
  sd_card      = love.graphics.newImage("assets/icons/sd-card-solid.png"),
  file_import  = love.graphics.newImage("assets/icons/file-import-solid.png"),
  refresh      = love.graphics.newImage("assets/icons/rotate-right-solid.png"),
  download     = love.graphics.newImage("assets/icons/download-solid.png"),
  wrench       = love.graphics.newImage("assets/icons/wrench-solid.png"),
  mag_glass    = love.graphics.newImage("assets/icons/magnifying-glass-solid.png"),
  user         = love.graphics.newImage("assets/icons/user.png"),
  performance  = love.graphics.newImage("assets/icons/performance.png"),
  region       = love.graphics.newImage("assets/icons/region.png"),
  cache_clean  = love.graphics.newImage("assets/icons/cache-clean.png"),
  button_a     = love.graphics.newImage("assets/inputs/switch_button_a.png"),
  button_b     = love.graphics.newImage("assets/inputs/switch_button_b.png"),
  button_x     = love.graphics.newImage("assets/inputs/switch_button_x.png"),
  button_y     = love.graphics.newImage("assets/inputs/switch_button_y.png"),
  dpad         = love.graphics.newImage("assets/inputs/switch_dpad_vertical_outline.png"),
  dpad_horizontal = love.graphics.newImage("assets/inputs/switch_dpad_horizontal_outline.png"),
  select       = love.graphics.newImage("assets/inputs/switch_button_sl.png"),
}

-- Get icon tint color from theme (uses label text color)
local icon_color = theme:read_color("label", "LABEL_TEXT", "#dfe6e9")

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

      -- Draw the icon with theme-based tint color
      love.graphics.setColor(icon_color)
      love.graphics.draw(icon, self.x + offsetX, self.y + offsetY, 0, sx, sy)

      love.graphics.pop()
    end,
  }
end

