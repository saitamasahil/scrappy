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

function badr:new(t)
  t = t or {}
  local _default = {
    x = 0,
    y = 0,
    height = 0,
    width = 0,
    parent = t.parent or nil,
    id = tostring(love.timer.getTime()),
    visible = true,
    children = {},
    focusable = false,
    focused = false
  }
  for key, value in pairs(t) do
    _default[key] = value
  end

  local instance = setmetatable(_default, badr)
  if instance.focusable and not (instance.root and instance.root.focusedElement) then
    instance.root = self:getRoot() -- Ensure the root reference is set
    -- if not instance.root.focusedElement then
    --   instance.root:setFocus(instance)
    -- end
  end
  return instance
end

function badr:createRoot(t)
  t = t or {}
  t.focusedElement = nil -- Initialize focusedElement specifically for root nodes
  return self:new(t)     -- Use `self:new` to create the root instance
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

-- Return any depth child with id
function badr.__pow(self, id)
  assert(type(id) == "string", 'Badr: Provided id must be a string.')
  -- Helper function to perform recursive search
  local function search(children)
    for _, child in ipairs(children) do
      if child.id == id then
        return child
      end
      -- Recursive call to search in the child’s children
      local found = search(child.children or {})
      if found then
        return found
      end
    end
  end

  -- Start the search from the current instance’s children
  return search(self.children)
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

function badr:update(dt)
  if self.onUpdate then
    self:onUpdate(dt)
  end
  for _, child in ipairs(self.children) do
    child:update(dt)
  end
end

-- Focus-related methods
-- Added by gabrielfvale

function badr:getRoot()
  local node = self
  while node.parent do
    node = node.parent -- Traverse up to find the root
  end
  return node
end

-- Set focus on a specific element
function badr:setFocus(element)
  local root = self:getRoot() -- Get the root node of the element
  if element.focusable then
    if root.focusedElement then
      root.focusedElement.focused = false -- Unfocus the current element
    end
    element.focused = true                -- Set the new element as focused
    root.focusedElement = element         -- Update the root's focused element
  end
end

local function gatherFocusableComponents(root)
  local focusableComponents = {}

  local function gather(component)
    if component.focusable then
      table.insert(focusableComponents, component)
    end
    for _, child in ipairs(component.children or {}) do
      gather(child) -- Recursively gather focusable components from all children
    end
  end

  gather(root)
  return focusableComponents
end

function badr:getNextFocusable(direction)
  local root = self:getRoot() -- Focus within the current root context
  local focusableComponents = gatherFocusableComponents(root)
  local currentIndex = nil

  for i, component in ipairs(focusableComponents) do
    if component == root.focusedElement then
      currentIndex = i
      break
    end
  end

  if not currentIndex then return nil end

  local nextIndex
  if direction == "previous" then
    nextIndex = currentIndex > 1 and currentIndex - 1 or #focusableComponents
  elseif direction == "next" then
    nextIndex = currentIndex < #focusableComponents and currentIndex + 1 or 1
  end

  return focusableComponents[nextIndex]
end

function badr:focusFirstElement()
  local root = self:getRoot() -- Get the root context of this element
  for _, child in ipairs(gatherFocusableComponents(root)) do
    root:setFocus(child)      -- Set focus to the first focusable element
    break
  end
end

-- Handles keyboard navigation
function badr:keypressed(key)
  local root = self:getRoot()
  if not root.focusedElement then return end

  if root.focusedElement.onKeyPress then
    root.focusedElement:onKeyPress(key)
  end

  local nextElement
  if (self.column and key == "up") or (self.row and key == "left") then
    nextElement = root.focusedElement:getNextFocusable("previous")
  elseif (self.column and key == "down") or (self.row and key == "right") then
    nextElement = root.focusedElement:getNextFocusable("next")
  end

  if nextElement then
    root:setFocus(nextElement)
  end
end

return setmetatable({ root = badr.createRoot, new = badr.new }, {
  __call = function(t, ...)
    return badr:new(...)
  end,
})
