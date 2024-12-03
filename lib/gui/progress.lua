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
    backgroundColor = theme:read_color("progress", "BAR_BACKGROUND", "#2d3436"),
    barColor = theme:read_color("progress", "BAR_COLOR", "#ffffff"),
    borderColor = theme:read_color("progress", "BAR_BORDER", "#636e72"),
    borderWidth = props.borderWidth or 2,
    -- draw function
    draw = function(self)
      if not self.visible then return end
      love.graphics.push()

      -- Draw background
      love.graphics.setColor(self.backgroundColor)
      love.graphics.rectangle('fill', self.x, self.y, self.width, self.height)

      -- Draw progress bar
      love.graphics.setColor(self.barColor)
      love.graphics.rectangle('fill', self.x, self.y, self.width * self.progress, self.height)

      -- Draw border if specified
      if self.borderWidth > 0 then
        love.graphics.setColor(self.borderColor)
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
