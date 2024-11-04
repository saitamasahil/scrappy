local ui = {
  registered_elements = {}, -- Store elements with unique identifiers
  focusable_elements = {},  -- Store focusable elements in order of appearance
  current_focus_id = nil,   -- Track the focused element by ID
  layout_stack = {},        -- Stack to track active layouts
  draw_queue = { n = 0 }    -- Draw queue
}
ui.__index = ui

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

local colors = {
  text = { 1, 1, 1 },
  background = { 0, 0, 0 },
  button = { 0.1, 0.1, 0.1 },
  button_highlight = { 0.2, 0.2, 0.2 },
  focus = { 0.8, 0.8, 0.2 }
}

local padding = 4
local line_height = 2
local icon_w, icon_h = 16, 16
local window_w, window_h = love.window.getMode()
local font = love.graphics.getFont()

function ui.new() -- Create a new UI instance
  local self = setmetatable({
    registered_elements = {},
    focusable_elements = {},
    current_focus_id = nil,
    layout_stack = {},
    draw_queue = { n = 0 }
  }, ui)
  -- self.registered_elements = {}
  -- self.focusable_elements = {}
  -- self.current_focus_id = nil
  -- self.layout_stack = {}
  -- self.draw_queue = { n = 0 }
  return self
end

function ui.button(label, callback, left_icon, right_icon)
  return {
    type = "button",
    label = label,
    callback = callback,
    left_icon = left_icon,
    right_icon = right_icon
  }
end

function ui.select(data, current, callback)
  return {
    type = "select",
    data = data,
    current = current,
    callback = callback
  }
end

function ui.icon_label(label, icon)
  return {
    type = "icon_label",
    label = label,
    icon = icon
  }
end

function ui.progress_bar(progress)
  return {
    type = "progress_bar",
    progress = progress
  }
end

function ui.multiline_text(text)
  return {
    type = "multiline_text",
    text = text
  }
end

function ui.checkbox(label, checked, callback)
  return {
    type = "checkbox",
    label = label,
    checked = checked,
    callback = callback
  }
end

local function draw_icon(icon, x, y)
  icon = icons[icon] or icons["warn"]
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

  local border = 2

  love.graphics.push()
  love.graphics.setScissor(x, y, w, h)
  love.graphics.setColor(focused and colors.focus or colors.button)
  love.graphics.rectangle("fill", x, y, w, h)
  love.graphics.setColor(focused and colors.button_highlight or colors.button)
  love.graphics.rectangle("fill", x + border, y + border, w - 2 * border, h - 2 * border)
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

local function draw_multiline_text(x, y, w, h, text)
  local _, wrappedtext = font:getWrap(text, w - 10)
  love.graphics.push()
  love.graphics.setColor(colors.button)
  love.graphics.rectangle("fill", x, y, w - 20, #wrappedtext * h)
  love.graphics.setColor(colors.text)
  love.graphics.printf(wrappedtext, x + 10, y + 5, w - 10, "left")
  love.graphics.pop()
end

local function draw_checkbox(x, y, w, h, label, checked, focused)
  local t = love.graphics.newText(font, label)
  local tw, th = t:getWidth(), t:getHeight()

  local border = 2

  love.graphics.push()
  love.graphics.setScissor(x, y, w, h)
  love.graphics.setColor(focused and colors.focus or colors.background)
  love.graphics.rectangle("fill", x, y, w, h)
  love.graphics.setColor(colors.background)
  love.graphics.rectangle("fill", x + border, y + border, w - 2 * border, h - 2 * border)
  love.graphics.setColor(colors.text)

  -- Draw the checkbox
  love.graphics.rectangle("fill", x + padding, y + icon_h / 2, icon_w, icon_h)
  love.graphics.setColor(checked and colors.focus or colors.button)
  love.graphics.rectangle("fill", x + padding + border, y + icon_h / 2 + border, icon_w - 2 * border, icon_h - 2 * border)
  love.graphics.setColor(colors.text)

  love.graphics.push()
  love.graphics.translate(x + icon_w + 2 * padding, y + h / 2)
  love.graphics.draw(t, 0, -th / 2 - line_height)
  love.graphics.pop()
  love.graphics.setScissor()
  love.graphics.pop()
end

local function generate_id(type, x, y)
  return type .. "_" .. tostring(x) .. "_" .. tostring(y)
end

function ui:setFocusById(id)
  self.current_focus_id = id
end

function ui:isFocused(id)
  return id == self.current_focus_id
end

function ui:register(fn, ...)
  local args = { ... }
  local nargs = select('#', ...)
  self.draw_queue.n = self.draw_queue.n + 1
  self.draw_queue[self.draw_queue.n] = function()
    fn(unpack(args, 1, nargs))
  end
end

function ui.load()
  -- TODO
end

function ui:draw()
  love.graphics.push('all')
  for i = self.draw_queue.n, 1, -1 do
    self.draw_queue[i]()
  end
  love.graphics.pop()
  self.draw_queue.n = 0
end

function ui:keypressed(key)
  local current_index = nil

  -- Find the current focus index in the focusable elements
  for i, element in ipairs(self.focusable_elements) do
    if element.id == self.current_focus_id then
      current_index = i
      break
    end
  end

  if current_index then
    local focused_element = self.focusable_elements[current_index]
    -- Handle navigation
    if key == "down" then
      -- Move focus down to the next element, wrapping around if needed
      local next_index = (current_index % #self.focusable_elements) + 1
      self:setFocusById(self.focusable_elements[next_index].id)
    elseif key == "up" then
      -- Move focus up to the previous element, wrapping around if needed
      local prev_index = ((current_index - 2) % #self.focusable_elements) + 1
      self:setFocusById(self.focusable_elements[prev_index].id)
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
    elseif focused_element.type == "checkbox" then
      if key == "return" then
        if focused_element.callback then
          focused_element.callback()
        end
      end
    end
  end
end

-- Start a layout with specified position, size, padding, and optional spacing between elements
function ui:layout(x, y, width, height, padding, spacing, direction)
  padding = padding or 0
  spacing = spacing or 0
  direction = direction or "vertical" -- Default to vertical stacking

  local last_layout = self.layout_stack[#self.layout_stack]

  -- Adjust position relative to the last layout if it exists
  if last_layout then
    x = last_layout.current_x + x
    y = last_layout.current_y + y

    -- Apply spacing if this layout is horizontal within the parent layout
    if last_layout.direction == "horizontal" then
      x = x + spacing
    elseif last_layout.direction == "vertical" then
      y = y + spacing
    end
  end

  local new_layout = {
    x = x + padding,
    y = y + padding,
    width = width - 2 * padding,
    height = height - 2 * padding,
    padding = padding,
    spacing = spacing,
    direction = direction,
    current_x = x + padding, -- For horizontal layouts, this tracks the next x position
    fixed_y = y + padding,   -- For horizontal layouts, this keeps y fixed for alignment
    current_y = y + padding  -- For vertical layouts, this is updated for stacking
  }

  table.insert(self.layout_stack, new_layout)
end

-- End the current layout and reset scissor
function ui:end_layout()
  local layout = table.remove(self.layout_stack)
  local parent_layout = self.layout_stack[#self.layout_stack]

  -- Update the parent's current position based on layout direction
  if parent_layout then
    if parent_layout.direction == "horizontal" then
      -- Move the parent's current x position to the right of the current layout, including spacing
      parent_layout.current_x = parent_layout.current_x + layout.width + parent_layout.spacing
    else
      -- Move the parent's current y position below the current layout, including spacing
      parent_layout.current_y = parent_layout.current_y + layout.height + parent_layout.spacing
    end
  end

  -- Reset scissor when ending a layout
  love.graphics.setScissor()
end

function ui:element(pos, element_data)
  local x, y, w, h = unpack(pos)
  local type = element_data.type

  -- Adjust width and height for icon labels if not provided
  if type == "icon_label" then
    w = w or font:getWidth(element_data.label) + icon_w + padding
    h = h or icon_h
  end

  -- Get the current layout and determine if it’s horizontal
  local current_layout = self.layout_stack[#self.layout_stack]
  if current_layout then
    if current_layout.direction == "horizontal" then
      -- Position element horizontally, keeping a fixed y position
      x = current_layout.current_x
      y = current_layout.fixed_y

      -- Update current_x for the next element, adding width and spacing
      current_layout.current_x = x + w + current_layout.spacing
    else
      -- For vertical layouts, use the stacking current_y position
      x = current_layout.current_x + x
      y = current_layout.current_y + y

      -- Update current_y for the next element, adding height and spacing
      current_layout.current_y = y + h + current_layout.spacing
    end

    -- Set scissor to clip elements within the layout's boundaries
    love.graphics.setScissor(current_layout.x, current_layout.y, current_layout.width, current_layout.height)
  end

  -- Generate a unique ID for the element
  local id = generate_id(type, x, y)

  -- Register focusable elements with callback
  if element_data.callback and not self.registered_elements[id] then
    self.registered_elements[id] = true
    table.insert(self.focusable_elements, { id = id, type = type, pos = pos, callback = element_data.callback })
    if not self.current_focus_id then
      self:setFocusById(id)
    end
  end

  -- Register drawing functions based on element type
  if type == "button" then
    self:register(draw_button, x, y, w, h, element_data.label, element_data.left_icon, element_data.right_icon,
      self:isFocused(id))
  elseif type == "select" then
    local label = element_data.data[element_data.current]
    self:register(draw_button, x, y, w, h, label, "chevron_left", "chevron_right", self:isFocused(id))
  elseif type == "icon_label" then
    self:register(draw_icon_label, element_data.label, element_data.icon, x, y)
  elseif type == "progress_bar" then
    self:register(draw_progress_bar, x, y, w, h, element_data.progress)
  elseif type == "multiline_text" then
    self:register(draw_multiline_text, x, y, w, h, element_data.text)
  elseif type == "checkbox" then
    self:register(draw_checkbox, x, y, w, h, element_data.label, element_data.checked, self:isFocused(id))
  end
end

return ui
