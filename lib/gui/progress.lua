local component = require("lib.gui.badr")
local theme     = require("helpers.config").theme

return function(props)
  local width = props.width or 100
  local height = props.height or 20
  local progress = math.max(0, math.min(props.progress or 0, 1)) -- Clamp progress between 0 and 1

  return component {
    id = props.id or tostring(love.timer.getTime()),
    x = props.x or 0,
    y = props.y or 0,
    width = width,
    height = height,
    progress = progress,
    -- colors
    -- colors (explicit overrides only)
    backgroundColor = props.backgroundColor,
    barColor = props.barColor,
    borderColor = props.borderColor,
    borderWidth = props.borderWidth or 2,
    -- draw function
    draw = function(self)
      if not self.visible then return end
      love.graphics.push()

      -- Resolve colors dynamically
      local backgroundColor = self.backgroundColor or theme:read_color("progress", "BAR_BACKGROUND", "#2d3436")
      local barColor = self.barColor or theme:read_color("progress", "BAR_COLOR", "#ffffff")
      local borderColor = self.borderColor or theme:read_color("progress", "BAR_BORDER", "#636e72")

      -- Draw background
      love.graphics.setColor(backgroundColor)
      love.graphics.rectangle('fill', self.x, self.y, self.width, self.height)

      -- Draw progress bar (Liquid Style)
      love.graphics.setColor(barColor)
      local barWidth = self.width * self.progress
      love.graphics.rectangle('fill', self.x, self.y, barWidth, self.height)
      
      -- Surface wave at the leading edge
      if self.progress > 0 and self.progress < 1 then
          local wave_x = self.x + barWidth
          local segments = 10
          local wave_w = 4
          love.graphics.setLineWidth(1)
          for i = 0, segments do
              local py = self.y + (i / segments) * self.height
              local offset = math.sin(py * 0.1 + love.timer.getTime() * 10) * wave_w * (1 - self.progress*0.5)
              love.graphics.line(wave_x, py, wave_x + offset, py)
          end
      end

      -- Draw border if specified
      if self.borderWidth > 0 then
        love.graphics.setColor(borderColor)
        love.graphics.setLineWidth(self.borderWidth)
        love.graphics.rectangle('line', self.x, self.y, self.width, self.height)
      end

      love.graphics.pop()
    end,
    -- update function
    onUpdate = function(self, dt)
      -- Update progress, clamping between 0 and 1
      self.progress = math.max(0, math.min(self.progress, 1))
    end,
    -- Set progress
    setProgress = function(self, newProgress)
      timer.tween(0.2, self, { progress = newProgress }, 'linear')
      -- self.progress = math.max(0, math.min(newProgress, 1))
    end
  }
end
