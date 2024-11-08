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
  RETURN = "return",
}

local cooldown_duration = 0.2
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
    if joystick:isGamepadDown("dpup") then
      trigger(input.events.UP)
    end
    if joystick:isGamepadDown("dpdown") then
      trigger(input.events.DOWN)
    end
    if joystick:isGamepadDown("a") then
      trigger(input.events.RETURN)
    end
    if joystick:isGamepadDown("b") then
      trigger(input.events.ESC)
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
    trigger(input.events.ESC)
  end

  if key == "left" then
    trigger(input.events.LEFT)
  end

  if key == "right" then
    trigger(input.events.RIGHT)
  end

  if key == "up" then
    trigger(input.events.UP)
  end

  if key == "down" then
    trigger(input.events.DOWN)
  end

  if key == "return" then
    trigger(input.events.RETURN)
  end
end

return input
