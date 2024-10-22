require("consts")

local splash = {
  finished = false
}
local logo
local rotation = { value = 0 }
local scale = { value = 1 }

local colors = {
  main = { 1, 1, 1 },
  background = { 1, 0, 0 },
}

function splash.load()
  logo = love.graphics.newImage("assets/muos-logo.png")
  timer.after(0,
    function(func)
      timer.tween(2, rotation, { value = rotation.value + 1 }, 'in-out-quad')
      timer.after(2, func)
    end)
  timer.after(2, function() splash.finished = true end)
end

function splash.draw()
  if splash.finished then return end
  local width, height = love.graphics.getDimensions()
  local logoScale = 0.5
  local logoWidth, logoHeight = logo:getWidth(), logo:getHeight()

  love.graphics.clear(0, 0, 0, 1)

  love.graphics.push()
  love.graphics.setColor(colors.background)
  love.graphics.translate(width / 2, height / 2)
  love.graphics.scale(scale.value)
  love.graphics.setColor(colors.main)
  love.graphics.draw(logo, 0, 0, rotation.value * math.pi, logoScale, logoScale, logo:getWidth() / 2,
    logo:getHeight() / 2)
  love.graphics.pop()
end

function splash.update(dt)
  timer.update(dt)
end

return splash
