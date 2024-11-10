require("globals")

local loading = {}
loading.__index = loading

local spinner = love.graphics.newImage("assets/muos-logo.png")
local spin

local rotation = { value = 0 }

local loading_timer = timer.new()

function loading.new(type, update_duration)
  return setmetatable({ type = type or "spinner", update_duration = update_duration or 0.5 }, loading)
end

function loading:load()
  spin = function()
    loading_timer:tween(self.update_duration, rotation, { value = rotation.value + 1 }, 'linear', spin)
  end
  if self.type == "spinner" then
    spin()
    -- elseif self.type == "pixel" then
    --   local width, height = 40, 18
    --   sprite_sheet = love.graphics.newImage("assets/loading.png")
    --   for y = 0, sprite_sheet:getHeight() - height, height do
    --     for x = 0, sprite_sheet:getWidth() - width, width do
    --       table.insert(sprite_anim.quads, love.graphics.newQuad(x, y, width, height, sprite_sheet:getDimensions()))
    --     end
    --   end
  else
    print("Unknown loading type: " .. self.type)
  end
end

function loading:update(dt)
  loading_timer:update(dt)
  -- if self.type == "pixel" then
  --   sprite_anim.current_time = sprite_anim.current_time + dt
  --   if sprite_anim.current_time >= self.update_duration then
  --     sprite_anim.current_time = sprite_anim.current_time - self.update_duration
  --   end
  -- end
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

  -- if self.type == "pixel" then
  --   local quad = sprite_anim.quads[math.floor(sprite_anim.current_time / self.update_duration * #sprite_anim.quads) + 1]
  --   love.graphics.push()
  --   love.graphics.setColor(1, 1, 1)
  --   love.graphics.translate(x - 40, y - 18)
  --   love.graphics.scale(scale)
  --   love.graphics.draw(sprite_sheet, quad, 0, 0)
  --   love.graphics.pop()
  -- end
end

function loading:reset()
  rotation.value = 0
end

return loading
