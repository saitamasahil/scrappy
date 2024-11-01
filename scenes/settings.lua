local settings = {}
local w_width, w_height = love.window.getMode()

function settings:load()
end

function settings:update(dt)
end

function settings:draw()
  love.graphics.push()
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, w_width, w_height)
  love.graphics.translate(w_width / 2, w_height / 2)
  love.graphics.setColor(1, 1, 1)
  love.graphics.print("settings", 0, 0)
  love.graphics.pop()
end

return settings
