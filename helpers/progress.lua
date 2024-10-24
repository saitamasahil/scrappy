local timer = require("lib.timer")

local progress = {
  timer = nil,
  duration = 1,
  finished = false
}

function progress.load()
  progress.timer = 0
  progress.finished = false
end

function progress.update(dt)
  if progress.timer ~= nil then
    progress.timer = progress.timer + dt
    if progress.timer > progress.duration then
      progress.timer = nil
      progress.finished = true
    end
  end
end

return progress
