local component = require 'lib.gui.badr'
local configs   = require 'helpers.config'

-- Icons definition (Paths)
local icon_paths = {
  caret_left   = "assets/icons/caret-left-solid.png",
  caret_right  = "assets/icons/caret-right-solid.png",
  folder       = "assets/icons/folder-open-regular.png",
  display      = "assets/icons/display-solid.png",
  canvas       = "assets/icons/object-group-solid.png",
  image        = "assets/icons/image-regular.png",
  controller   = "assets/icons/gamepad-solid.png",
  warn         = "assets/icons/triangle-exclamation-solid.png",
  info         = "assets/icons/circle-info-solid.png",
  cd           = "assets/icons/compact-disc-solid.png",
  square       = "assets/icons/square-regular.png",
  square_check = "assets/icons/square-check-solid.png",
  sd_card      = "assets/icons/sd-card-solid.png",
  file_import  = "assets/icons/file-import-solid.png",
  refresh      = "assets/icons/rotate-right-solid.png",
  download     = "assets/icons/download-solid.png",
  wrench       = "assets/icons/wrench-solid.png",
  mag_glass    = "assets/icons/magnifying-glass-solid.png",
  user         = "assets/icons/user.png",
  performance  = "assets/icons/performance.png",
  region       = "assets/icons/region.png",
  cache_clean  = "assets/icons/cache-clean.png",
  backup       = "assets/icons/backup.png",
  cache        = "assets/icons/cache.png",
  theme        = "assets/icons/theme.png",
  accent       = "assets/icons/accent.png",
  mode         = "assets/icons/mode.png",
  presets      = "assets/icons/presets.png",
  custom       = "assets/icons/custom.png",
  button_a     = "assets/inputs/switch_button_a.png",
  button_b     = "assets/inputs/switch_button_b.png",
  button_x     = "assets/inputs/switch_button_x.png",
  button_y     = "assets/inputs/switch_button_y.png",
  dpad         = "assets/inputs/switch_dpad_vertical_outline.png",
  dpad_horizontal = "assets/inputs/switch_dpad_horizontal_outline.png",
  select       = "assets/inputs/switch_button_sl.png",
  clock        = "assets/icons/clock.png",
  time         = "assets/icons/time.png",
  timer        = "assets/icons/timer.png",
  offline      = "assets/icons/offline.png",
  downloading  = "assets/icons/download-solid.png",
  generating   = "assets/icons/generate.png",
  source       = "assets/icons/source.png",
  artwork      = "assets/icons/artwork.png",
  save         = "assets/icons/save.png",
  preview      = "assets/icons/preview.png",
  manage       = "assets/icons/manage.png",
  capture      = "assets/icons/capture.png",
  remove       = "assets/icons/remove.png",
  grid         = "assets/icons/grid.png",
  showcase     = "assets/icons/showcase.png",
  password     = "assets/icons/password.png",
  sound        = "assets/icons/sound.png",
}

local icons = {}
local icon_metadata = {}

-- Helper to scan image data for content bounds (trimmed of transparency)
local function get_content_bounds(data)
  local w, h = data:getDimensions()
  local x_min, y_min = w, h
  local x_max, y_max = 0, 0
  local found = false
  for x = 0, w - 1 do
    for y = 0, h - 1 do
      local _, _, _, a = data:getPixel(x, y)
      if a > 0 then
        x_min = math.min(x_min, x)
        y_min = math.min(y_min, y)
        x_max = math.max(x_max, x)
        y_max = math.max(y_max, y)
        found = true
      end
    end
  end
  if not found then return 0, 0, w, h end
  return x_min, y_min, (x_max - x_min) + 1, (y_max - y_min) + 1
end

-- Initialize icons and metadata
for name, path in pairs(icon_paths) do
  local info = love.filesystem.getInfo(path)
  if info then
    local data = love.image.newImageData(path)
    icons[name] = love.graphics.newImage(data)
    local x, y, w, h = get_content_bounds(data)
    icon_metadata[name] = { x = x, y = y, w = w, h = h }
  end
end

return function(props)
  local name = props.name
  local img = icons[name] or icons["warn"]
  local meta = icon_metadata[name] or icon_metadata["warn"]

  local boxSize = props.size or (24 * (_G.scale or 1))
  
  -- Normalization Scaling: 
  -- We scale based on the ACTUAL content bounds to ensure consistent visual weight
  local scale = boxSize / math.max(meta.w, meta.h)
  local sx, sy = scale, scale

  -- Center accurately based on content bounds
  local offsetX = (boxSize - meta.w * sx) / 2 - meta.x * sx
  local offsetY = (boxSize - meta.h * sy) / 2 - meta.y * sy

  return component {
    id = props.id or tostring(love.timer.getTime()),
    x = props.x or 0,
    y = props.y or 0,
    width = boxSize,
    height = boxSize,
    focusable = false,
    draw = function(self)
      love.graphics.push()
      -- Transparent background box
      love.graphics.setColor(1, 1, 1, 0)
      love.graphics.rectangle("fill", self.x, self.y, self.width, self.height)

      -- Normalized icon with theme tint
      local icon_color = configs.theme:read_color("label", "LABEL_TEXT", "#dfe6e9")
      love.graphics.setColor(icon_color)
      love.graphics.draw(img, self.x + offsetX, self.y + offsetY, 0, sx, sy)
      love.graphics.pop()
    end,
  }
end
