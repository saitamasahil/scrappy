local input = {}

local joystick
local state = {
  last_event = nil,
  current_event = nil,
  trigger = false,
}

input.events = {
  LEFT = "left",
  RIGHT = "right",
  UP = "up",
  DOWN = "down",
  ESC = "escape",
}

local cooldown_duration = 0.5
local last_trigger_time = -cooldown_duration

local function can_trigger_global(dt)
  local current_time = love.timer.getTime()
  if current_time - last_trigger_time >= cooldown_duration then
    last_trigger_time = current_time
    return true
  end
  return false
end

local function trigger(event)
  if can_trigger_global() then
    state.last_event = state.current_event
    state.current_event = event
    state.trigger = true
    -- print("Triggered: " .. event)  -- Debug
  end
end

function input.load()
  -- Initialize joystick
  local joysticks = love.joystick.getJoysticks()
  if #joysticks > 0 then
    joystick = joysticks[1]
  end
end

function input.update(dt)
  if joystick then
    if joystick:isGamepadDown("dpleft") then
      trigger(input.events.LEFT)
    end
    if joystick:isGamepadDown("dpright") then
      trigger(input.events.RIGHT)
    end
  end
end

function input.onEvent(callback)
  if state.trigger then
    state.trigger = false
    callback(state.current_event)
  end
end

function love.keypressed(key)
  if key == "escape" then
    love.event.quit()
    trigger(input.events.ESC)
  end

  if key == "left" then
    trigger(input.events.LEFT)
  end

  if key == "right" then
    trigger(input.events.RIGHT)
  end

  if key == "space" then
    -- local sample_artwork = WORK_DIR .. "/templates/" .. artworks[state.current_artwork] .. ".xml"
    -- skyscraper.fetch_artwork("snes", sample_artwork)
    -- skyscraper.update_artwork("snes", sample_artwork)
  end
end

return input
