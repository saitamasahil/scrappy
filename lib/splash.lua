require("globals")

local splash = {
  finished = false
}

local app_name = love.graphics.newText(love.graphics.getFont(), "Scrappy")
local credits = love.graphics.newText(love.graphics.getFont(), "by gabrielfvale")

local logo
local anim = { value = 0 }
local splash_timer = timer.new()

local colors = {
  main = { 1, 1, 1 },
  background = { 0, 0, 0 },
}

function splash.load(delay)
  delay = delay or 1
  logo = love.graphics.newImage("assets/muos-logo.png")
  splash_timer:tween(delay, anim, { value = 1 }, 'in-out-cubic')
  splash_timer:after(delay + 0.2, function()
    splash_timer:tween(0.5, anim, { value = 0 }, 'in-out-cubic', function()
      splash.finished = true
    end)
  end)
end

function splash.draw()
  if splash.finished then return end
  local width, height = love.graphics.getDimensions()
  local logo_scale = 1
  -- local logoWidth, half_height = logo:getWidth(), logo:getHeight()
  local half_height = logo:getHeight() / 2

  love.graphics.clear(colors.background)

  love.graphics.push()
  love.graphics.translate(width / 2, height / 2)
  love.graphics.setColor(colors.main)
  love.graphics.draw(logo, 0, -anim.value * half_height, 0, logo_scale,
    logo_scale,
    logo:getWidth() / 2,
    half_height)
  love.graphics.setColor(1, 1, 1, anim.value)
  love.graphics.push()
  love.graphics.translate(0, half_height)
  love.graphics.scale(1.5)
  love.graphics.draw(app_name, -app_name:getWidth() / 2,
    -anim.value * app_name:getHeight())
  love.graphics.pop()
  love.graphics.push()
  love.graphics.setColor(1, 1, 1, 0.5)
  love.graphics.scale(0.5)
  love.graphics.draw(credits, -credits:getWidth() / 2, height - credits:getHeight() - 40)
  love.graphics.pop()
  love.graphics.setColor(colors.background)
  love.graphics.pop()
end

function splash.update(dt)
  splash_timer:update(dt)
end

function splash.finish()
  splash.finished = true
end

return splash
