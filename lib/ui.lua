local ui = {
  icons = {
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
  }
}

local draw_queue = { n = 0 }

local colors = {
  text = { 1, 1, 1 },
  background = { 0, 0, 0 },
  button = { 0.1, 0.1, 0.1 },
  button_highlight = { 0.5, 0.5, 0.5 }
}

local padding = 4
local line_height = 2
local icon_w, icon_h = 16, 16
local window_w, window_h = love.window.getMode()
local font = love.graphics.getFont()

local function draw_icon(icon, x, y)
  icon = ui.icons[icon] or ui.icons["warn"]
  local iw, ih = icon:getWidth(), icon:getHeight()
  love.graphics.push()
  -- love.graphics.rectangle("fill", x, y, icon_w, icon_h)
  love.graphics.translate(icon_w / 2, icon_h / 2)
  love.graphics.draw(icon, x - iw / 2, y - ih / 2)
  love.graphics.pop()
end

local function draw_button(x, y, w, h, label, left_icon, right_icon)
  local t = love.graphics.newText(font, label)
  local tw, th = t:getWidth(), t:getHeight()

  love.graphics.push()
  love.graphics.setScissor(x, y, w, h)
  love.graphics.setColor(colors.button)
  love.graphics.rectangle("fill", x, y, w, h)
  love.graphics.setColor(colors.button_highlight)
  love.graphics.rectangle("line", x, y, w, h)
  love.graphics.setColor(colors.text)
  if left_icon then
    draw_icon(left_icon, x + padding, y + h / 2 - icon_h / 2)
  end
  if right_icon then
    draw_icon(right_icon, x + w - icon_w - padding, y + h / 2 - icon_h / 2)
  end
  love.graphics.push()
  love.graphics.translate(x + w / 2, y + h / 2)
  love.graphics.draw(t, -tw / 2, -th / 2 - line_height)
  love.graphics.pop()
  love.graphics.setScissor()
  love.graphics.pop()
end

local function draw_icon_label(label, icon, x, y)
  local t = love.graphics.newText(font, label)
  draw_icon(icon, x, y)
  love.graphics.push()
  love.graphics.translate(x + icon_w, y + icon_h / 2)
  love.graphics.draw(t, padding, -t:getHeight() / 2 - line_height)
  love.graphics.pop()
end

function ui.register(fn, ...)
  local args = { ... }
  local nargs = select('#', ...)
  draw_queue.n = draw_queue.n + 1
  draw_queue[draw_queue.n] = function()
    fn(unpack(args, 1, nargs))
  end
end

function ui.load()
  -- TODO
end

function ui.draw()
  -- love.graphics.push()
  -- love.graphics.translate(w_width / 2, w_height / 2)
  -- love.graphics.setColor(1, 1, 1, 1)
  -- for i, element in ipairs(ui.elements) do
  --   if element.type == "button" then
  --     draw_button(element.label, element.x, element.y, element.w, element.h, "chevron_left", "chevron_right")
  --   end
  -- end
  -- love.graphics.pop()

  love.graphics.push('all')
  for i = draw_queue.n, 1, -1 do
    draw_queue[i]()
  end
  love.graphics.pop()
  draw_queue.n = 0
end

function ui.update(dt)
  -- TODO
end

local function draw_container(x, y, w, h, fn)
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.setColor(colors.background)
  love.graphics.rectangle("fill", 0, 0, w, h)
  love.graphics.setColor(colors.text)
  love.graphics.rectangle("line", 0, 0, w, h)
  love.graphics.pop()
end

function ui.element(type, pos, ...)
  local x, y, w, h = unpack(pos)
  if type == "button" then
    local label, left_icon, right_icon = unpack({ ... }, 1)
    ui.register(draw_button, x, y, w, h, label, left_icon, right_icon)
  end
  if type == "select" then
    local data, current = unpack({ ... }, 1, 2)
    ui.register(draw_button, x, y, w, h, data[current], "chevron_left", "chevron_right")
  end
  if type == "icon_label" then
    local label, icon = unpack({ ... }, 1, 2)
    ui.register(draw_icon_label, label, icon, x, y)
  end
  -- if type == "container" then
  --   ui.register(draw_container, x, y, w, h, ...)
  -- end
  -- if type == "button" then
  --   ui.elements[#ui.elements + 1] = {
  --     type = type,
  --     label = label,
  --     x = x,
  --     y = y,
  --     w = w,
  --     h = h,
  --     state = {
  --       focus = false,
  --       click = false
  --     }
  --   }
  -- end
end

return ui
