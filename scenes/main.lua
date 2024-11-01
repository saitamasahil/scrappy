local main = {}
local w_width, w_height = love.window.getMode()

function main:load()
end

function main:update(dt)
end

function main:draw()
  love.graphics.push()
  love.graphics.translate(w_width / 2, w_height / 2)
  love.graphics.print("main", 0, 0)
  love.graphics.pop()
end

return main
