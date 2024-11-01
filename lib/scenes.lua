local nativefs = require("lib.nativefs")

local scenes = {
  states = {},
  focus = {},
  action = { switch = false, push = false, pop = false, newid = 0 }
}
scenes.__index = scenes

function scenes:load(initial_state)
  for _, file in ipairs(nativefs.getDirectoryItems("scenes")) do
    if string.find(file, ".lua") then
      self.states[string.gsub(file, ".lua", "")] = require("scenes." .. string.gsub(file, ".lua", ""))
    end
  end
  if initial_state then
    self:push(initial_state)
  end
end

function scenes:push(state)
  self.states[state]:load()
  self.focus[#self.focus + 1] = state
end

function scenes:pop()
  local cfocus = self:currentFocus()
  if #self.focus > 1 then
    if (self.states[cfocus].close ~= nil) then
      self.states[cfocus]:close()
    end
    self.focus[#self.focus] = nil
  end
end

function scenes:switch(state)
  for i, v in ipairs(self.focus) do
    self.focus[i] = nil
  end
  self.focus = {}
  self:push(state)
end

function scenes:currentFocus()
  return self.focus[#self.focus]
end

function scenes:update(dt)
  self.states[self:currentFocus()]:update(dt)
end

function scenes:draw()
  for i, v in pairs(self.focus) do
    self.states[v]:draw()
  end
end

return scenes
