require("globals")

local loading = {}
loading.__index = loading

local spinner

local rotation = { value = 0 }
local width = { value = 0 }

local loading_timer = timer.new()

function loading.new(type, update_duration)
  return setmetatable({ type = type or "spinner", update_duration = update_duration or 0.5 }, loading)
end

function loading:load()
  if self.type == "spinner" then
    spinner = love.graphics.newImage("assets/muos-logo.png")
    -- spinner
    loading_timer:after(0,
      function(func)
        loading_timer:tween(self.update_duration, rotation, { value = rotation.value + 1 }, 'linear')
        loading_timer:after(self.update_duration, func)
      end)
  else
    print("Unknown loading type: " .. self.type)
  end
end

function loading:update(dt)
  loading_timer:update(dt)
end

function loading:draw(x, y, scale)
  if self.type == "spinner" then
    love.graphics.push()
    love.graphics.setColor(1, 1, 1)
    love.graphics.translate(x, y)
    love.graphics.rotate(rotation.value)
    love.graphics.draw(spinner, 0, 0, rotation.value * math.pi, scale, scale, spinner:getWidth() / 2,
      spinner:getHeight() / 2)
    love.graphics.pop()
  end
end

function loading:reset()
  rotation.value = 0
  width.value = 0
end

return loading
