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
    play = love.graphics.newImage("assets/icons/Play.png"),
  },
  registered_elements = {}, -- Store elements with unique identifiers
  focusable_elements = {},  -- Store focusable elements in order of appearance
  current_focus_id = nil,   -- Track the focused element by ID
  active_layout = nil       -- Track the currently active layout
}

local draw_queue = { n = 0 }

local colors = {
  text = { 1, 1, 1 },
  background = { 0, 0, 0 },
  button = { 0.1, 0.1, 0.1 },
  button_highlight = { 0.5, 0.5, 0.5 },
  focus = { 0.5, 0.5, 0.2 }
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

local function draw_button(x, y, w, h, label, left_icon, right_icon, focused)
  local t = love.graphics.newText(font, label)
  local tw, th = t:getWidth(), t:getHeight()

  love.graphics.push()
  love.graphics.setScissor(x, y, w, h)
  love.graphics.setColor(focused and colors.focus or colors.button)
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

local function draw_progress_bar(x, y, w, h, progress)
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.setColor(colors.button)
  love.graphics.rectangle("fill", 0, 0, w, h)
  love.graphics.setColor(colors.button_highlight)
  love.graphics.rectangle("line", 0, 0, w, h)
  love.graphics.setColor(colors.text)
  love.graphics.rectangle("fill", 0, 0, progress * w, h)
  love.graphics.pop()
end

local function generate_id(type, x, y)
  return type .. "_" .. tostring(x) .. "_" .. tostring(y)
end

function ui.setFocusById(id)
  ui.current_focus_id = id
end

local function isFocused(id)
  return id == ui.current_focus_id
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

function ui.keypressed(key)
  local current_index = nil

  -- Find the current focus index in the focusable elements
  for i, element in ipairs(ui.focusable_elements) do
    if element.id == ui.current_focus_id then
      current_index = i
      break
    end
  end

  if current_index then
    local focused_element = ui.focusable_elements[current_index]
    -- Handle navigation
    if key == "down" then
      -- Move focus down to the next element, wrapping around if needed
      local next_index = (current_index % #ui.focusable_elements) + 1
      ui.setFocusById(ui.focusable_elements[next_index].id)
    elseif key == "up" then
      -- Move focus up to the previous element, wrapping around if needed
      local prev_index = ((current_index - 2) % #ui.focusable_elements) + 1
      ui.setFocusById(ui.focusable_elements[prev_index].id)
    end

    -- Handle specific actions based on element type and keys
    if focused_element.type == "select" then
      if (key == "left" or key == "right") and focused_element.callback then
        focused_element.callback(key) -- Call the callback function with the key as argument
      end
    elseif focused_element.type == "button" then
      if key == "return" and focused_element.callback then
        focused_element.callback() -- Call the onPress function
      end
    end
  end
end

function ui.layout(x, y, width, height, padding, spacing)
  padding = padding or 0
  spacing = spacing or 0
  ui.active_layout = {
    x = x + padding,
    y = y + padding,
    width = width - 2 * padding,
    height = height - 2 * padding,
    padding = padding,
    spacing = spacing,
    current_x = x + padding, -- Track horizontal position for left-to-right layout
    current_y = y + padding  -- Track vertical position for top-to-bottom layout
  }
end

-- End the current layout
function ui.end_layout()
  love.graphics.setScissor()
  ui.active_layout = nil
end

function ui.element(type, pos, ...)
  local x, y, w, h = unpack(pos)
  if type == "icon_label" then
    w, h = font:getWidth(select(1, ...)) + icon_w + padding, icon_h
  end

  -- Apply active layout if it exists, adjusting for auto-spacing
  if ui.active_layout then
    -- Use current_x and current_y based on layout settings, starting from top with spacing
    x = ui.active_layout.current_x + x
    y = ui.active_layout.current_y + y

    -- Update `current_y` or `current_x` for the next element
    ui.active_layout.current_y = y + h + ui.active_layout.spacing

    -- Set scissor to clip elements within the layout area
    love.graphics.setScissor(ui.active_layout.x, ui.active_layout.y, ui.active_layout.width, ui.active_layout.height)
  end

  local id = generate_id(type, x, y)

  if not ui.registered_elements[id] then
    ui.registered_elements[id] = true
    if type == "button" or type == "select" then
      local callback = select(1, ...)
      table.insert(ui.focusable_elements, { id = id, type = type, pos = pos, callback = callback })
      if not ui.current_focus_id then
        ui.setFocusById(id)
      end
    end
  end

  if type == "button" or type == "select" then
    local label, left_icon, right_icon
    if type == "button" then
      _, label, left_icon, right_icon = unpack({ ... }, 1)
    elseif type == "select" then
      local _, data, current = unpack({ ... }, 1, 3)
      label, left_icon, right_icon = data[current], "chevron_left", "chevron_right"
    end
    ui.register(draw_button, x, y, w, h, label, left_icon, right_icon, isFocused(id))
  elseif type == "icon_label" then
    local label, icon = unpack({ ... }, 1, 2)
    ui.register(draw_icon_label, label, icon, x, y)
  elseif type == "progress_bar" then
    local progress = unpack({ ... }, 1, 1)
    ui.register(draw_progress_bar, x, y, w, h, progress)
  end
end

return ui
