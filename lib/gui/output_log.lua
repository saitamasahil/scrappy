local component = require("lib.gui.badr")

return function(props)
  local font = props.font or love.graphics.getFont()
  local padding = props.padding or 10

  local width = props.width or 0
  local height = props.height or 0

  -- Per-line marquee state: keyed by line content string
  -- Each entry: { offset = number, timer = number }
  local line_scrolls = {}
  local scroll_speed = 40 -- pixels per second
  local scroll_pause = 1.5 -- seconds to pause at start before scrolling

  return component {
    id = props.id or tostring(love.timer.getTime()),
    width = width,
    height = height,
    font = font,
    text = "",
    onUpdate = function(self, dt)
      if not dt then return end

      local usable = self.width - padding * 2

      -- Update scroll state for each currently visible line
      local active_keys = {}
      for s in self.text:gmatch("[^\r\n]+") do
        active_keys[s] = true
        local lw = self.font:getWidth(s)
        if lw > usable then
          -- This line needs scrolling
          if not line_scrolls[s] then
            line_scrolls[s] = { offset = 0, timer = 0 }
          end
          local ls = line_scrolls[s]
          ls.timer = ls.timer + dt
          if ls.timer > scroll_pause then
            ls.offset = ls.offset + scroll_speed * dt
            local total_scroll = lw - usable + 60
            if ls.offset > total_scroll then
              ls.offset = 0
              ls.timer = 0
            end
          end
        end
      end

      -- Clean up scroll state for lines that are no longer visible
      for k, _ in pairs(line_scrolls) do
        if not active_keys[k] then
          line_scrolls[k] = nil
        end
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
      local usable = self.width - padding * 2

      -- Draw text from bottom-up, with per-line horizontal scroll
      local offset = self.height - totalTextHeight
      for i = 1, #lines do
        local line = lines[i]
        local x_off = 0
        local ls = line_scrolls[line]
        if ls then
          x_off = -ls.offset
        end
        love.graphics.print(line, self.x + padding + x_off, self.y + offset)
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
