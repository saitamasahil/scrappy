local component = require("lib.gui.badr")

return function(props)
  local font = props.font or love.graphics.getFont()
  local padding = props.padding or 10

  local width = props.width or 0
  local height = props.height or 0

  -- Marquee scrolling state
  local scroll_offset = 0
  local scroll_speed = 40 -- pixels per second
  local scroll_pause = 1.5 -- seconds to pause at start before scrolling
  local scroll_timer = 0
  local prev_text = ""

  return component {
    id = props.id or tostring(love.timer.getTime()),
    width = width,
    height = height,
    font = font,
    text = "",
    onUpdate = function(self, dt)
      if not dt then return end
      -- Reset scroll when text changes
      if self.text ~= prev_text then
        prev_text = self.text
        scroll_offset = 0
        scroll_timer = 0
      end

      -- Find the widest line
      local max_w = 0
      for s in self.text:gmatch("[^\r\n]+") do
        local lw = self.font:getWidth(s)
        if lw > max_w then max_w = lw end
      end

      local usable = self.width - padding * 2
      if max_w > usable then
        scroll_timer = scroll_timer + dt
        if scroll_timer > scroll_pause then
          scroll_offset = scroll_offset + scroll_speed * dt
          -- Reset when the longest line has fully scrolled through
          local total_scroll = max_w - usable + 60 -- extra gap before looping
          if scroll_offset > total_scroll then
            scroll_offset = 0
            scroll_timer = 0
          end
        end
      else
        scroll_offset = 0
        scroll_timer = 0
      end
    end,
    draw = function(self)
      love.graphics.push()
      love.graphics.setColor(0, 0, 0, 0.5)
      love.graphics.rectangle("fill", self.x, self.y, self.width, self.height)
      love.graphics.setColor(1, 1, 1)
      
      -- Use real scissor instead of stencil for text clipping
      local sx, sy, sw, sh = love.graphics.getScissor()
      
      local tx1, ty1 = love.graphics.transformPoint(self.x, self.y)
      local tx2, ty2 = love.graphics.transformPoint(self.x + self.width, self.y + self.height)
      local nx, ny = math.min(tx1, tx2), math.min(ty1, ty2)
      local nw, nh = math.abs(tx2 - tx1), math.abs(ty2 - ty1)
      
      if sx then
          local ix = math.max(sx, nx)
          local iy = math.max(sy, ny)
          local ir = math.min(sx + sw, nx + nw)
          local ib = math.min(sy + sh, ny + nh)
          if ir > ix and ib > iy then
              love.graphics.setScissor(ix, iy, ir - ix, ib - iy)
          else
              love.graphics.setScissor(nx, ny, 0, 0)
          end
      else
          love.graphics.setScissor(nx, ny, nw, nh)
      end

      -- Split the text into lines
      local lines = {}
      for s in self.text:gmatch("[^\r\n]+") do
        table.insert(lines, s)
      end

      -- Calculate the total height of all the lines
      local totalTextHeight = #lines * self.font:getHeight()

      -- Draw text from bottom-up, with horizontal scroll for long lines
      local offset = self.height - totalTextHeight
      local usable = self.width - padding * 2
      for i = 1, #lines do
        local lw = self.font:getWidth(lines[i])
        local x_off = 0
        if lw > usable then
          x_off = -scroll_offset
        end
        love.graphics.print(lines[i], self.x + padding + x_off, self.y + offset)
        offset = offset + self.font:getHeight()
      end

      if sx then
          love.graphics.setScissor(sx, sy, sw, sh)
      else
          love.graphics.setScissor()
      end
      love.graphics.pop()
    end
  }
end
