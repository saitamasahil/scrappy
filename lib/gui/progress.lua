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
      local accentColor = self.barColor or theme:read_color("button", "BUTTON_FOCUS", "#ffffff")
      -- Avoid invisible bar: if accent is too close to background, fall back to theme BAR_COLOR
      local function colors_similar(c1, c2)
          local dr = math.abs((c1[1] or 0) - (c2[1] or 0))
          local dg = math.abs((c1[2] or 0) - (c2[2] or 0))
          local db = math.abs((c1[3] or 0) - (c2[3] or 0))
          return (dr + dg + db) < 0.08
      end
      local barColor = accentColor
      if colors_similar(accentColor, backgroundColor) then
          barColor = theme:read_color("progress", "BAR_COLOR", "#ffffff")
      end
      local borderColor = self.borderColor or theme:read_color("progress", "BAR_BORDER", "#636e72")

      -- Draw background
      love.graphics.setColor(backgroundColor)
      love.graphics.rectangle('fill', self.x, self.y, self.width, self.height)

      -- Determine displayed progress
      local current_p = self.anim_progress or self.progress

      -- Draw progress bar (Liquid Style)
      love.graphics.setColor(barColor)
      local barWidth = self.width * current_p
      love.graphics.rectangle('fill', self.x, self.y, barWidth, self.height)
      
      -- Surface wave at the leading edge
      if current_p > 0 and current_p < 1 then
          local wave_x = self.x + barWidth
          local segments = 10
          local wave_w = 4
          love.graphics.setLineWidth(1)
          for i = 0, segments do
              local py = self.y + (i / segments) * self.height
              local offset = math.sin(py * 0.1 + love.timer.getTime() * 10) * wave_w * (1 - current_p*0.5)
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
      
      -- Smooth interpolation (prevent Euler explosion on lag spikes)
      self.anim_progress = self.anim_progress or self.progress
      local speed = 10 * dt
      if speed >= 1 then
          self.anim_progress = self.progress
      else
          self.anim_progress = self.anim_progress + (self.progress - self.anim_progress) * speed
      end
      -- Safe clamp
      self.anim_progress = math.max(0, math.min(self.anim_progress, 1))
    end,
    -- Set progress
    setProgress = function(self, newProgress)
      -- Use direct assignment instead of tween since onUpdate handles it
      self.progress = math.max(0, math.min(newProgress, 1))
    end
  }
end
