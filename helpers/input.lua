local input = {}

local joystick
local state = {
  last_event = nil,
  current_event = nil,
  trigger = false,
}

-- Hold-to-scroll configuration/state for directional navigation
local repeat_delay = 0.28  -- initial delay before auto-repeat starts
local repeat_rate  = 0.06  -- time between repeats while holding
local holding = {
  dir = nil,           -- one of input.events.LEFT/RIGHT/UP/DOWN
  start_time = 0,      -- when the hold started
  started = false,     -- whether repeat stage has begun
  last_fire = 0,       -- last time we emitted a repeat
}

input.events = {
  LEFT = "left",
  RIGHT = "right",
  UP = "up",
  DOWN = "down",
  ESC = "escape",
  RETURN = "return",
  MENU = "lalt",
  PREV = "[",
  NEXT = "]",
}

input.joystick_mapping = {
  ["dpleft"] = input.events.LEFT,
  ["dpright"] = input.events.RIGHT,
  ["dpup"] = input.events.UP,
  ["dpdown"] = input.events.DOWN,
  ["a"] = input.events.RETURN,
  ["b"] = input.events.ESC,
  ["back"] = input.events.MENU,
  -- Use LÖVE standard names for shoulder buttons
  ["leftshoulder"] = input.events.PREV,
  ["rightshoulder"] = input.events.NEXT,
}

local cooldown_duration = 0.2
local last_trigger_time = -cooldown_duration

local function can_trigger_global()
  local current_time = love.timer.getTime()
  if current_time - last_trigger_time >= cooldown_duration then
    last_trigger_time = current_time
    return true
  end
  return false
end

-- Emit an event into the input queue. When bypass is true, ignore the global cooldown
-- (used for hold-to-scroll repeats) while keeping cooldown for discrete presses.
local function emit(event, bypass)
  if bypass or can_trigger_global() then
    state.last_event = state.current_event
    state.current_event = event
    state.trigger = true
  end
end

function input.load()
  -- Initialize joystick
  local joysticks = love.joystick.getJoysticks()
  if #joysticks > 0 then
    joystick = joysticks[1]
    -- Log basic joystick info for debugging
    local name = joystick:getName() or "unknown"
    local guid = (joystick.getGUID and joystick:getGUID()) or "n/a"
    local is_gamepad = (joystick.isGamepad and joystick:isGamepad()) and "yes" or "no"
    print(string.format("[input] joystick detected: name='%s' guid='%s' is_gamepad=%s", name, guid, is_gamepad))
  else
    print("[input] no joystick detected")
  end
end

function input.update(dt)
  -- Process hold-to-scroll repeats for directional navigation without polling axes.
  if holding.dir then
    local now = love.timer.getTime()
    if not holding.started then
      if now - holding.start_time >= repeat_delay then
        holding.started = true
        holding.last_fire = now
        emit(holding.dir, true)
      end
    else
      if now - holding.last_fire >= repeat_rate then
        holding.last_fire = now
        emit(holding.dir, true)
      end
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
  for _, k in pairs(input.events) do
    if key == k then
      emit(key, false)
    end
  end
  -- Start hold for directional keys and shoulder paging (PREV/NEXT)
  if key == input.events.LEFT or key == input.events.RIGHT or key == input.events.UP or key == input.events.DOWN
    or key == input.events.PREV or key == input.events.NEXT then
    holding.dir = key
    holding.start_time = love.timer.getTime()
    holding.started = false
    holding.last_fire = holding.start_time
  end
end

function love.keyreleased(key)
  if key == holding.dir then
    holding.dir = nil
    holding.started = false
  end
end

function love.gamepadpressed(js, button)
  -- Use mapping table to trigger events
  local event = input.joystick_mapping[button]
  if event then
    emit(event, false)
    -- Start hold for directional and paging (shoulder) gamepad events
    if event == input.events.LEFT or event == input.events.RIGHT or event == input.events.UP or event == input.events.DOWN
      or event == input.events.PREV or event == input.events.NEXT then
      holding.dir = event
      holding.start_time = love.timer.getTime()
      holding.started = false
      holding.last_fire = holding.start_time
    end
  end
end

function love.gamepadreleased(js, button)
  local event = input.joystick_mapping[button]
  if event and event == holding.dir then
    holding.dir = nil
    holding.started = false
  end
end

return input
