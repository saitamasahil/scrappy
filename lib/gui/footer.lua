local component = require 'lib.gui.badr'
local label     = require 'lib.gui.label'

local function footer()
  return component { row = true, gap = 40 }
      + label { text = "Select", icon = "button_a" }
      + label { text = "Back/Quit", icon = "button_b" }
      + label { text = "Navigate", icon = "dpad" }
      + label { text = "Settings", icon = "select" }
end

return footer
