local component = require 'lib.gui.badr'
local label     = require 'lib.gui.label'

local function footer()
  return component { row = true, gap = 40 }
      + label { id = "footer_a", text = "Select", icon = "button_a", buoyant = true }
      + label { id = "footer_b", text = "Back/Quit", icon = "button_b", buoyant = true }
      + label { id = "footer_dpad", text = "Navigate", icon = "dpad", buoyant = true }
      + label { id = "footer_select", text = "Settings", icon = "select", buoyant = true }
end

return footer
