local component = require('lib.gui.badr')
local configs   = require('helpers.config')

return function(props)
  local theme = configs.theme
  local height = props.height or
      200                                                                  -- Height of the scroll container viewport
  local width = props.width or 200
  -- Visual properties moved to component
  local scrollbarWidth = theme:read_number("scroll", "SCROLLBAR_WIDTH", 6) -- Width of the scroll bar

  -- No per-node offsets needed when children don't use absolute scissor.

  return component {
    x = props.x or 0,
    y = props.y or 0,
    width = width,
    height = height,
    children = props.children or {},
    focusable = false,

    barColor = props.barColor,
    scrollY = 0,
    targetScrollY = 0,
    scrollVelocity = 0,
    scrollbarBulge = 0,

    -- Scroll control methods
    scrollTo = function(self, position)
      -- Clamp the scroll position to be within the content bounds
      self.targetScrollY = math.max(0, math.min(position, self:getContentHeight() - height))
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
      local childY = focusedChild.y - self.y - self.targetScrollY -- Calculate relative to where the screen WILL be
      -- Dynamic margin so section headers above the focused control are fully visible
      local margin = math.max(24, math.min(80, math.floor(height * 0.12)))
      if childY < margin then
        -- Scroll up slightly more to reveal the header above the focused control
        self:scrollTo(self.scrollY + childY - margin)
      elseif childY + focusedChild.height > height - margin then
        -- Scroll down and keep a bottom margin
        self:scrollTo(self.scrollY + childY + focusedChild.height - height + margin)
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
      local scrollbarY = (self.scrollY / contentHeight) * self.height

      -- Resolve colors dynamically
      local barColor = self.barColor or theme:read_color("scroll", "SCROLLBAR_COLOR", "#636e72")

      -- Liquid UI: Scrollbar Bulge and Stretch
      local bulge = (self.scrollbarBulge or 0) * 4
      local bw = scrollbarWidth + bulge
      
      -- Draw the scroll bar on the left of the container
      love.graphics.setColor(barColor)
      love.graphics.rectangle("fill", self.x - bw - 2, self.y + scrollbarY - bulge/2, bw, scrollbarHeight + bulge, 4, 4)
    end,

    draw = function(self)
      -- Transform-aware scissor: setScissor uses screen coordinates, so we convert
      -- the container bounds using the current transform.
      local prevx, prevy, prevw, prevh = love.graphics.getScissor()
      local x1, y1 = love.graphics.transformPoint(self.x, self.y)
      local x2, y2 = love.graphics.transformPoint(self.x + self.width, self.y + self.height)
      local sx, sy = math.min(x1, x2), math.min(y1, y2)
      local sw, sh = math.abs(x2 - x1), math.abs(y2 - y1)
      love.graphics.setScissor(sx, sy, sw, sh)

      -- Draw each child with adjusted position for scrolling
      love.graphics.push()
      love.graphics.translate(0, -self.scrollY)
      for _, child in ipairs(self.children) do
        child:draw()
      end
      love.graphics.pop()

      love.graphics.setScissor(prevx, prevy, prevw, prevh)

      -- Draw the scroll bar
      love.graphics.push()
      self:drawScrollbar()
      love.graphics.pop()
    end,

    update = function(self, dt)
      -- Smoothly interpolate scroll position toward target
      local prevY = self.scrollY
      self.scrollY = self.scrollY + (self.targetScrollY - self.scrollY) * 15 * dt
      self.scrollVelocity = (self.scrollY - prevY) / dt
      
      local targetBulge = math.min(1.0, math.abs(self.scrollVelocity) / 1000)
      self.scrollbarBulge = (self.scrollbarBulge or 0) + (targetBulge - (self.scrollbarBulge or 0)) * 10 * dt
      
      -- Update children with the current scroll offset
      for _, child in ipairs(self.children) do
        child:update(dt)
      end
      self:scrollToFocused() -- Ensure focused element is within view
    end,
  }
end
