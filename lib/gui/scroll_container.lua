local component = require('lib.gui.badr')
local theme     = require('helpers.config').theme

return function(props)
  local height = props.height or
      200                                                                  -- Height of the scroll container viewport
  local width = props.width or 200
  local scrollY = 0                                                        -- Initialize scroll position
  local scrollbarWidth = theme:read_number("scroll", "SCROLLBAR_WIDTH", 6) -- Width of the scroll bar

  return component {
    x = props.x or 0,
    y = props.y or 0,
    width = width,
    height = height,
    children = props.children or {},
    focusable = false,

    barColor = theme:read_color("scroll", "SCROLLBAR_COLOR", "#636e72"),

    -- Scroll control methods
    scrollTo = function(self, position)
      -- Clamp the scroll position to be within the content bounds
      scrollY = math.max(0, math.min(position, self:getContentHeight() - height))
    end,

    scrollToFocused = function(self)
      local focusedChild = self:getRoot().focusedElement
      if not focusedChild then return end

      -- Check if the focused element is within the scope of this scroll container
      local function isDescendantOf(component, parent)
        while component do
          if component == parent then return true end
          component = component.parent
        end
        return false
      end

      if not isDescendantOf(focusedChild, self) then return end

      -- Determine the relative position of the focused child within the container
      local childY = focusedChild.y - self.y - scrollY -- Relative Y position accounting for scroll offset
      if childY < 0 then
        -- Scroll up to bring the child into view
        self:scrollTo(scrollY + childY)
      elseif childY + focusedChild.height > height then
        -- Scroll down to bring the child into view
        self:scrollTo(scrollY + childY + focusedChild.height - height)
      end
    end,

    getContentHeight = function(self)
      -- Calculate the combined height of all children to determine content bounds
      local totalHeight = 0
      for _, child in ipairs(self.children) do
        totalHeight = totalHeight + child.height
      end
      return totalHeight
    end,

    drawScrollbar = function(self)
      -- Calculate scroll bar height and position based on the scroll position
      local contentHeight = self:getContentHeight()
      if contentHeight <= self.height then return end -- No scrollbar if content fits

      local scrollbarHeight = (self.height / contentHeight) * self.height
      local scrollbarY = (scrollY / contentHeight) * self.height

      -- Draw the scroll bar on the left of the container
      love.graphics.setColor(self.barColor) -- Set the scrollbar color (light gray)
      love.graphics.rectangle("fill", self.x - scrollbarWidth - 2, self.y + scrollbarY, scrollbarWidth, scrollbarHeight)
    end,

    draw = function(self)
      -- Apply clipping for the scroll container viewport
      love.graphics.setScissor(self.x, self.y, self.width, self.height)

      -- Draw each child with adjusted position for scrolling
      for _, child in ipairs(self.children) do
        love.graphics.push()
        love.graphics.translate(0, -scrollY) -- Adjust for scroll position
        child:draw()
        love.graphics.pop()
      end

      -- Remove clipping after drawing the children
      love.graphics.setScissor()

      -- Draw the scroll bar
      self:drawScrollbar()
    end,

    update = function(self, dt)
      -- Update children with the current scroll offset
      for _, child in ipairs(self.children) do
        child:update(dt)
      end
      self:scrollToFocused() -- Ensure focused element is within view
    end,
  }
end
