--
-- Badr
--
-- Copyright (c) 2024 Nabeel20
--
-- This library is free software; you can redistribute it and/or modify it
-- under the terms of the MIT license. See LICENSE for details.
--
local badr = {}
badr.__index = badr

-- Focused element reference
badr.focusedElement = nil

-- Key navigation mappings for directional movement
local keyMappings = {
  up = "up",
  down = "down",
  left = "left",
  right = "right"
}

function badr:new(t)
  t = t or {}
  local _default = {
    x = 0,
    y = 0,
    height = 0,
    width = 0,
    parent = { x = 0, y = 0, visible = true },
    id = tostring(love.timer.getTime()),
    visible = true,
    children = {},
    focusable = false, -- Defines if an element is focusable
    focused = false    -- Tracks if the element is currently focused
  }
  for key, value in pairs(t) do
    _default[key] = value
  end

  local instance = setmetatable(_default, badr)
  if instance.focusable and not badr.focusedElement then
    badr:setFocus(instance) -- Set initial focus to the first focusable element
  end
  return instance
end

function badr.__add(self, component)
  if type(component) ~= "table" or component == nil then return end

  component.parent = self
  component.x = self.x + component.x
  component.y = self.y + component.y

  local childrenSize = { width = 0, height = 0 }
  for _, child in ipairs(self.children) do
    childrenSize.width = childrenSize.width + child.width
    childrenSize.height = childrenSize.height + child.height
  end

  local gap = self.gap or 0
  local lastChild = self.children[#self.children] or {}

  if self.column then
    component.y = (lastChild.height or 0) + (lastChild.y or self.y)
    if #self.children > 0 then
      component.y = component.y + gap
    end
    self.height = math.max(self.height, childrenSize.height + component.height + gap * #self.children)
    self.width = math.max(self.width, component.width)
  end
  if self.row then
    component.x = (lastChild.width or 0) + (lastChild.x or self.x)
    if #self.children > 0 then
      component.x = component.x + gap
    end
    self.width = math.max(self.width, childrenSize.width + component.width + gap * #self.children)
    self.height = math.max(self.height, component.height)
  end

  if #component.children > 0 then
    for _, child in ipairs(component.children) do
      child:updatePosition(component.x, component.y)
    end
  end
  table.insert(self.children, component)
  return self
end

-- Remove child
function badr.__sub(self, component)
  if self % component.id then
    for index, child in ipairs(self.children) do
      if child.id == component.id then
        table.remove(self.children, index)
      end
    end
  end
  return self
end

-- Returns child with specific id
function badr.__mod(self, id)
  assert(type(id) == "string", 'Badar; Provided id must be a string.')
  for _, child in ipairs(self.children) do
    if child.id == id then
      return child
    end
  end
end

function badr:isMouseInside()
  local mouseX, mouseY = love.mouse.getPosition()
  return mouseX >= self.x and mouseX <= self.x + self.width and
      mouseY >= self.y and
      mouseY <= self.y + self.height
end

function badr:draw()
  if not self.visible then return end;
  if #self.children > 0 then
    for _, child in ipairs(self.children) do
      child:draw()
    end
  end
end

function badr:updatePosition(x, y)
  self.x = self.x + x
  self.y = self.y + y
  for _, child in ipairs(self.children) do
    child:updatePosition(x, y)
  end
end

function badr:animate(props)
  props(self)
  for _, child in ipairs(self.children) do
    child:animate(props)
  end
end

function badr:update()
  if self.onUpdate then
    self:onUpdate()
  end
  for _, child in ipairs(self.children) do
    child:update()
  end
end

-- Focus-related methods
-- Added by gabrielfvale

-- Set focus on a specific element
function badr:setFocus(element)
  if element.focusable then
    if badr.focusedElement then
      badr.focusedElement.focused = false -- Unfocus the current element
    end
    element.focused = true                -- Set the new element as focused
    badr.focusedElement = element         -- Update the global reference
  end
end

function badr:getNextFocusable(direction)
  if not self.parent then return nil end -- If there’s no parent, no siblings exist

  local siblings = self.parent.children
  local currentIndex = nil

  -- Find the index of the currently focused element within its siblings
  for i, sibling in ipairs(siblings) do
    if sibling == self then
      currentIndex = i
      break
    end
  end

  if not currentIndex then return nil end

  -- Search for the next focusable element based on the direction
  local nextIndex = currentIndex
  repeat
    if direction == "previous" then
      nextIndex = nextIndex > 1 and nextIndex - 1 or #siblings -- Wrap to the last sibling
    elseif direction == "next" then
      nextIndex = nextIndex < #siblings and nextIndex + 1 or 1 -- Wrap to the first sibling
    end

    -- Return the next sibling if it’s focusable
    if siblings[nextIndex].focusable then
      return siblings[nextIndex]
    end
  until nextIndex == currentIndex -- Stop if we loop back to the original element

  return nil                      -- If no focusable element is found, return nil
end

-- Handles keyboard navigation
function badr:keypressed(key)
  if not badr.focusedElement then return end

  if badr.focusedElement.onKeyPress then
    badr.focusedElement:onKeyPress(key)
  end

  local nextElement
  if (self.column and key == "up") or (self.row and key == "left") then
    nextElement = badr.focusedElement:getNextFocusable("previous")
  elseif (self.column and key == "down") or (self.row and key == "right") then
    nextElement = badr.focusedElement:getNextFocusable("next")
  end

  if nextElement then
    badr:setFocus(nextElement) -- Set focus to the new element
  end
end

return setmetatable({ new = badr.new }, {
  __call = function(t, ...)
    return badr:new(...)
  end,
})
