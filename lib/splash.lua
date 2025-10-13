require("globals")

local splash = { finished = false }

-- Dynamically sized texts
local app_name
local app_version_text
local credits
local last_w, last_h

local function refresh_texts()
  local w, h = love.graphics.getDimensions()
  last_w, last_h = w, h
  -- Font sizes scale with height; clamp to sensible min/max for handhelds
  local title_size = math.max(18, math.min(96, math.floor(h * 0.10)))
  local sub_size   = math.max(12, math.min(48, math.floor(h * 0.035)))

  local title_font = love.graphics.newFont(title_size)
  local sub_font   = love.graphics.newFont(sub_size)

  app_name = love.graphics.newText(title_font, "Scrappy")
  app_version_text = love.graphics.newText(sub_font, _G.version)
  credits = love.graphics.newText(sub_font, "by gabrielfvale")
end

local logo = love.graphics.newImage("assets/scrappy_logo.png")
local anim = { value = 0 }

local colors = {
  main = { 1, 1, 1 },
  background = { 0, 0, 0 },
}

function splash.load(delay)
  delay = delay or 1
  timer.tween(delay, anim, { value = 1 }, 'in-out-cubic')
  timer.after(delay + 0.2, function()
    timer.tween(0.5, anim, { value = 0 }, 'in-out-cubic', function()
      splash.finished = true
    end)
  end)
  refresh_texts()
end

function splash.draw()
  if splash.finished then return end
  local width, height = love.graphics.getDimensions()
  if width ~= last_w or height ~= last_h or not app_name then
    refresh_texts()
  end
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
  love.graphics.draw(app_name, -app_name:getWidth() * 0.5,
    -anim.value * app_name:getHeight())
  love.graphics.pop()
  love.graphics.push()
  love.graphics.setColor(1, 1, 1, 0.5)
  love.graphics.translate(0, height * 0.5 - 20)
  local v_h = app_version_text:getHeight()
  local c_h = credits:getHeight()
  local spacing = math.max(6, math.floor(c_h * 0.4))
  -- Draw credits above version with a bit of spacing
  love.graphics.draw(app_version_text, -app_version_text:getWidth() * 0.5, -v_h)
  love.graphics.draw(credits, -credits:getWidth() * 0.5, -v_h - c_h - spacing)
  love.graphics.pop()
  love.graphics.setColor(colors.background)
  love.graphics.pop()
end

function splash.finish()
  splash.finished = true
end

return splash
