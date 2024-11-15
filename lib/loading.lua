require("globals")

local loading = {}
loading.__index = loading

local logo = love.graphics.newImage("assets/scrappy_logo.png")
local spin, flash_start, flash_end, highlight

local rotation = { value = 0 }
local opacity = { value = 1 }

local highlight_position = { x = -logo:getWidth(), y = -logo:getHeight() } -- Start above and to the left of the logo

function loading.new(type, update_duration)
  return setmetatable({ type = type or "spinner", update_duration = update_duration or 0.5 }, loading)
end

function loading:load()
  spin = function()
    timer.tween(self.update_duration, rotation, { value = rotation.value + 1 }, 'linear', spin)
  end
  flash_start = function()
    timer.tween(self.update_duration * 0.5, opacity, { value = 0.3 }, 'in-out-quad', flash_end)
  end
  flash_end = function()
    timer.tween(self.update_duration * 0.5, opacity, { value = 1 }, 'in-out-quad', flash_start)
  end
  highlight = function()
    timer.tween(
      self.update_duration,
      highlight_position,
      { x = logo:getWidth(), y = logo:getHeight() },
      'linear',
      function()
        highlight_position.x = -logo:getWidth()
        highlight_position.y = -logo:getHeight()
        highlight()
      end
    )
  end

  if self.type == "spinner" then
    spin()
  elseif self.type == "flash" then
    flash_start()
  elseif self.type == "highlight" then
    highlight()
  else
    print("Unknown loading type: " .. self.type)
  end
end

local function moving_stencil()
  local w, h = 10, logo:getHeight() * 2
  love.graphics.push()
  love.graphics.translate(highlight_position.x, highlight_position.y)
  love.graphics.rotate(45 * math.pi / 180)
  love.graphics.rectangle("fill", -w * 0.5, -h * 0.5, w, h)
  love.graphics.pop()
end

function loading:draw(x, y, scale)
  if self.type == "spinner" then
    love.graphics.push()
    love.graphics.setColor(1, 1, 1)
    love.graphics.translate(x, y)
    love.graphics.rotate(rotation.value)
    love.graphics.draw(logo, 0, 0, rotation.value * math.pi, scale, scale, logo:getWidth() / 2,
      logo:getHeight() / 2)
    love.graphics.pop()
  end

  if self.type == "flash" then
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.setColor(1, 1, 1, opacity.value)
    love.graphics.draw(logo, 0, 0, 0, scale, scale, logo:getWidth() * 0.5, logo:getHeight() * 0.5)
    love.graphics.pop()
  end

  if self.type == "highlight" then
    love.graphics.push()
    love.graphics.translate(x, y)

    love.graphics.setColor(1, 1, 1, 0.3)
    love.graphics.draw(logo, 0, 0, 0, scale, scale, logo:getWidth() * 0.5, logo:getHeight() * 0.5)

    love.graphics.stencil(moving_stencil, "replace", 1)
    love.graphics.setStencilTest("equal", 1)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(logo, 0, 0, 0, scale, scale, logo:getWidth() * 0.5, logo:getHeight() * 0.5)

    love.graphics.setStencilTest()

    love.graphics.pop()
  end
end

function loading:reset()
  rotation.value = 0
end

return loading
