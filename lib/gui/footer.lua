local component = require 'lib.gui.badr'
local label     = require 'lib.gui.label'

local function footer(props)
  props = props or {}
  local hints = props.hints or {}
  
  local text_a = hints.a or "Select"
  local text_b = hints.b or "Back"
  local text_dpad = hints.dpad or "Navigate"
  local text_select = hints.select or "Settings"
  
  local f = component { row = true, gap = 15 * _G.scale }
  
  if text_a ~= false then
    f = f + label { id = "footer_a", text = text_a, icon = "button_a", buoyant = true }
  end
  if text_b ~= false then
    f = f + label { id = "footer_b", text = text_b, icon = "button_b", buoyant = true }
  end
  if text_dpad ~= false then
    f = f + label { id = "footer_dpad", text = text_dpad, icon = "dpad", buoyant = true }
  end
  if text_select ~= false then
    f = f + label { id = "footer_select", text = text_select, icon = "select", buoyant = true }
  end
  
  return f
end

return footer
