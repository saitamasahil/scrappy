local nativefs = require("lib.nativefs")

local scenes = {
    states = {},
    focus = {},
    action = {
        switch = false,
        push = false,
        pop = false,
        newid = 0
    }
}
scenes.__index = scenes

local pending_action = nil
local pending_timer = 0
local DELAY_TIME = 0.08 -- 80ms is perfect for a quick click animation

function scenes:load(initial_state)
    for _, file in ipairs(nativefs.getDirectoryItems("scenes")) do
        if string.find(file, "%.lua$") then
            self.states[string.gsub(file, "%.lua$", "")] = require("scenes." .. string.gsub(file, "%.lua$", ""))
        end
    end
    if initial_state then
        self:_do_push(initial_state)
    end
end

function scenes:isTransitionPending()
    return pending_action ~= nil
end

function scenes:push(state)
    if pending_action then return end
    pending_action = { type = "push", state = state }
    pending_timer = DELAY_TIME
end

function scenes:pop()
    if pending_action then return end
    pending_action = { type = "pop" }
    pending_timer = DELAY_TIME
end

function scenes:switch(state)
    if pending_action then return end
    pending_action = { type = "switch", state = state }
    pending_timer = DELAY_TIME
end

function scenes:_do_push(state)
    require("helpers.input").ignoreCurrentPresses()
    self.states[state]:load()
    self.focus[#self.focus + 1] = state
    self.scene_fade = 0
end

function scenes:_do_pop()
    local cfocus = self:currentFocus()
    if #self.focus > 1 then
        if (self.states[cfocus].close ~= nil) then
            self.states[cfocus]:close()
        end
        self.focus[#self.focus] = nil

        local new_focus_id = self:currentFocus()
        if new_focus_id and self.states[new_focus_id].resume then
            self.states[new_focus_id]:resume()
        end
        require("helpers.input").ignoreCurrentPresses()
        self.scene_fade = 0
    end
end

function scenes:_do_switch(state)
    for i, _ in ipairs(self.focus) do
        self.focus[i] = nil
    end
    self.focus = {}
    self:_do_push(state)
end

function scenes:currentFocus()
    return self.focus[#self.focus]
end

function scenes:keypressed(key)
    if pending_action then return end
    self.states[self:currentFocus()]:keypressed(key)
end

function scenes:update(dt)
    if pending_action then
        pending_timer = pending_timer - dt
        if pending_timer <= 0 then
            local action = pending_action
            pending_action = nil
            if action.type == "push" then
                self:_do_push(action.state)
            elseif action.type == "pop" then
                self:_do_pop()
            elseif action.type == "switch" then
                self:_do_switch(action.state)
            end
        end
    end

    if self.scene_fade then
        self.scene_fade = math.min(1, self.scene_fade + dt * 8)
    end
    self.states[self:currentFocus()]:update(dt)
end

function scenes:draw()
    local top = self:currentFocus()
    if top then
        self.states[top]:draw()
        if self.scene_fade and self.scene_fade < 1 then
            love.graphics.setColor(0, 0, 0, 1 - self.scene_fade)
            love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
        end
    end
end

return scenes
