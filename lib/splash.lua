require("globals")

local splash = {
  finished = false
}

local app_name = love.graphics.newText(love.graphics.getFont(), "Scrappy")
local version = love.graphics.newText(love.graphics.getFont(), version)
local credits = love.graphics.newText(love.graphics.getFont(), string.format("by gabrielfvale"))

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
  local half_logo_height = logo:getHeight() * 0.5

  love.graphics.clear(colors.background)

  love.graphics.push()
  love.graphics.translate(width * 0.5, height * 0.5)
  love.graphics.setColor(colors.main)
  love.graphics.draw(logo, 0, -anim.value * half_logo_height, 0, logo_scale,
    logo_scale,
    logo:getWidth() * 0.5,
    half_logo_height)
  love.graphics.setColor(1, 1, 1, anim.value)
  love.graphics.push()
  love.graphics.translate(0, half_logo_height)
  love.graphics.scale(1.5)
  love.graphics.draw(app_name, -app_name:getWidth() * 0.5,
    -anim.value * app_name:getHeight())
  love.graphics.pop()
  love.graphics.push()
  love.graphics.setColor(1, 1, 1, 0.5)
  love.graphics.translate(0, height * 0.5 - 20)
  love.graphics.scale(0.75)
  love.graphics.draw(credits, -credits:getWidth() * 0.5, -credits:getHeight() - 20)
  love.graphics.draw(version, -version:getWidth() * 0.5, -version:getHeight())
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
