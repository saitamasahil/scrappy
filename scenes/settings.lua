local scenes = require("lib.scenes")
local ui = require("lib.ui")

local main_ui = ui.new()
local padding = 10

local settings = {}
local w_width, w_height = love.window.getMode()

function settings:load()
end

function settings:update(dt)
  main_ui:layout(0, 0, w_width, w_height, padding, padding)
  main_ui:element("icon_label", { 0, 0 }, "Settings", "at")
  main_ui:element("button",
    { 0, 0, w_width / 2, 30 },
    function()
      scenes:pop()
    end,
    "Back",
    "left_arrow"
  )
  main_ui:end_layout()
end

function settings:draw()
  love.graphics.push()
  love.graphics.setColor(0, 0, 0, 1)
  main_ui:draw()
  love.graphics.pop()
end

function settings:keypressed(key)
  main_ui:keypressed(key)
  if key == "escape" then
    scenes:pop()
  end
end

return settings
