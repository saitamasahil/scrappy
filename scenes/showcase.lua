local scenes    = require("lib.scenes")
local configs   = require("helpers.config")
local sound     = require("lib.sound")

local component        = require 'lib.gui.badr'
local label            = require 'lib.gui.label'

local theme = configs.theme
local w_width, w_height = love.window.getMode()

local showcase = {}
local footer
local current_index = 1
local total_images = 10
local images = {}
local load_queue = {}
local load_timer = 0
local initial_delay = 0.5 -- Wait 0.5s before background loading starts

-- Animation state
local anim_x = 0
local prev_index = 1
local transition_t = 1
local img_scale = 1
local target_img_scale = 1

function showcase:load()
    current_index = 1
    prev_index = 1
    transition_t = 1
    anim_x = 0
    img_scale = 1
    target_img_scale = 1
    load_timer = 0
    
    -- 1. Load the "Hero" images immediately (Current + Neighbors)
    -- This ensures the first swipe in either direction is ALWAYS smooth.
    self:load_image(1)
    self:load_image(2)
    self:load_image(total_images)
    
    -- 2. Queue the rest of the images
    load_queue = {}
    for i = 1, total_images do
        if not images[i] then
            table.insert(load_queue, i)
        end
    end
    
    -- Footer
    footer = component { row = true, gap = 40 * _G.scale }
        + label { id = "footer_b", text = "Back", icon = "button_b" }
        + label { id = "footer_swipe", text = "Next/Prev", icon = "dpad_horizontal" }
    footer:updatePosition(w_width * 0.5 - footer.width * 0.5, w_height - footer.height - (15 * _G.scale))
end

function showcase:load_image(index)
    if not images[index] then
        local path = "showcase/showcase" .. index .. ".png"
        if not love.filesystem.getInfo(path) then
            path = WORK_DIR .. "/showcase/showcase" .. index .. ".png"
        end
        if love.filesystem.getInfo(path) then
            images[index] = love.graphics.newImage(path)
        end
    end
end

function showcase:update(dt)
    if footer then footer:update(dt) end
    
    -- 3. Spaced Background Loading
    -- We only load when NOT transitioning and after an initial delay
    if transition_t >= 1 then
        if initial_delay > 0 then
            initial_delay = initial_delay - dt
        elseif #load_queue > 0 then
            load_timer = load_timer + dt
            -- Load one image every 0.15 seconds to keep the UI responsive
            if load_timer > 0.15 then
                local idx = table.remove(load_queue, 1)
                self:load_image(idx)
                load_timer = 0
            end
        end
    end
    
    -- Smooth transition timer
    if transition_t < 1 then
        transition_t = math.min(1, transition_t + dt * 6)
    end
    
    -- Scale "squish" feedback
    img_scale = img_scale + (target_img_scale - img_scale) * 15 * dt
    if math.abs(target_img_scale - 1) < 0.01 then target_img_scale = 1 end
end

function showcase:draw_image(index, offset_x, alpha)
    local img = images[index]
    if not img then 
        -- Show loading text if user is faster than the background loader
        love.graphics.setColor(1, 1, 1, alpha * 0.3)
        love.graphics.printf("Loading...", offset_x, w_height/2, w_width, "center")
        return 
    end
    
    local iw, ih = img:getDimensions()
    local target_w = w_width * 0.85
    local target_h = w_height - (100 * _G.scale)
    local scale = math.min(target_w / iw, target_h / ih) * img_scale
    
    local x = math.floor((w_width - iw * scale) / 2 + offset_x)
    local y = math.floor((w_height - (40 * _G.scale) - ih * scale) / 2)
    
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.draw(img, x, y, 0, scale, scale)
end

function showcase:draw()
    love.graphics.clear(theme:read_color("main", "BACKGROUND", "#000000"))
    
    local ease = 1 - math.pow(1 - transition_t, 3)
    local slide_offset = (1 - ease) * w_width * anim_x
    
    if transition_t < 1 then
        self:draw_image(prev_index, -slide_offset, 1 - ease)
    end
    
    self:draw_image(current_index, (anim_x == 1 and w_width or -w_width) * (1 - ease), ease)

    -- Index dots
    local accent = theme:read_color("button", "BUTTON_FOCUS", "#cbaa0f")
    local dot_size = 6 * _G.scale
    local dot_gap = 14 * _G.scale
    local total_w = (total_images - 1) * dot_gap
    local start_x = (w_width - total_w) / 2
    local dot_y = w_height - (75 * _G.scale)
    
    for i = 1, total_images do
        if i == current_index then
            love.graphics.setColor(accent[1], accent[2], accent[3], ease)
            love.graphics.circle("fill", start_x + (i - 1) * dot_gap, dot_y, dot_size * img_scale)
        else
            love.graphics.setColor(1, 1, 1, 0.2)
            love.graphics.circle("fill", start_x + (i - 1) * dot_gap, dot_y, dot_size * 0.7)
        end
    end

    if footer then footer:draw() end
end

function showcase:next()
    if transition_t < 0.6 then return end
    prev_index = current_index
    current_index = current_index + 1
    if current_index > total_images then current_index = 1 end
    
    -- Ensure the NEXT image is loaded if we're moving fast
    self:load_image(current_index)
    
    anim_x = 1
    transition_t = 0
    img_scale = 0.96
    sound.play("nav_move")
end

function showcase:prev()
    if transition_t < 0.6 then return end
    prev_index = current_index
    current_index = current_index - 1
    if current_index < 1 then current_index = total_images end
    
    -- Ensure the PREV image is loaded if we're moving fast
    self:load_image(current_index)
    
    anim_x = -1
    transition_t = 0
    img_scale = 0.96
    sound.play("nav_move")
end

function showcase:keypressed(key)
    if key == "escape" or key == "lalt" then
        sound.play("nav_back")
        scenes:pop()
    elseif key == "left" then
        self:prev()
    elseif key == "right" then
        self:next()
    end
end

function showcase:gamepadpressed(joystick, button)
    if button == "b" then
        sound.play("nav_back")
        scenes:pop()
        return true
    elseif button == "dpleft" then
        self:prev()
        return true
    elseif button == "dpright" then
        self:next()
        return true
    end
    return false
end

return showcase
