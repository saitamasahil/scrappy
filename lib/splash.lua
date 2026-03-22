require("globals")

local splash = {
    finished = false
}

-- Dynamically sized texts
local app_name
local app_version_text
local credits_author
local credits_maintainer
local credits_font
local last_w, last_h

local function refresh_texts()
    local w, h = love.graphics.getDimensions()
    last_w, last_h = w, h
    -- Font sizes scale with height; clamp to sensible min/max for handhelds
    local title_size = math.max(18, math.min(96, math.floor(h * 0.10)))
    local sub_size = math.max(12, math.min(48, math.floor(h * 0.035)))

    local title_font = love.graphics.newFont(title_size)
    local sub_font = love.graphics.newFont(sub_size)
    credits_font = love.graphics.newFont(sub_size + 2) -- slight increase for credits

    app_name = love.graphics.newText(title_font, "Scrappy")
    app_version_text = love.graphics.newText(sub_font, _G.version)
    credits_author = love.graphics.newText(credits_font, "Author — gabrielfvale")
    credits_maintainer = love.graphics.newText(credits_font, "Maintainer — saitamasahil")
end

local logo = love.graphics.newImage("assets/scrappy_logo.png")
local anim = {
    pop_scale = 0,         -- Phase 1: Logo pops in
    slide_y = 0,           -- Phase 2: Logo slides up
    title_alpha = 0,       -- Phase 2: Title fades/slides
    title_y_offset = 20,
    version_alpha = 0,     -- Phase 3: Cascade
    version_y_offset = 20,
    maintainer_alpha = 0,
    maintainer_y_offset = 20,
    author_alpha = 0,
    author_y_offset = 20,
    fade_out = 1,          -- Final sequence to exit
    wave_2_x = 0,
    reveal_style = "wave",  -- wave | bubbles | droplet
    bubble_progress = 0,
    drop_y = -100,
    impact_r = 0
}

local configs = require("helpers.config")
local theme = configs.theme
local bg_color = theme:read_color("main", "BACKGROUND", "#000000")
local text_color = theme:read_color("label", "LABEL_TEXT", "#dfe6e9")

local colors = {
    main = text_color,
    background = bg_color
}

function splash.load(delay)
    delay = delay or 1
    
    -- Reset state if re-entered (e.g. from About screen)
    anim.pop_scale = 0
    anim.slide_y = 0
    anim.title_alpha = 0
    anim.title_y_offset = 20
    anim.version_alpha = 0
    anim.version_y_offset = 20
    anim.maintainer_alpha = 0
    anim.maintainer_y_offset = 20
    anim.author_alpha = 0
    anim.author_y_offset = 20
    anim.fade_out = 1
    anim.wave_2_x = 0
    anim.bubble_progress = 0
    anim.drop_y = -100
    anim.impact_r = 0
    
    local styles = {"wave", "bubbles", "droplet"}
    anim.reveal_style = styles[math.random(#styles)]
    
    splash.finished = false
    splash.is_revealing = false

    -- PHASE 1: Logo Pop-In (Elastic/Bouncy)
    timer.tween(0.8, anim, { pop_scale = 1.0 }, 'out-elastic')

    -- PHASE 2: Logo Slides Up, Main Title Fades In
    timer.after(0.7, function()
        timer.tween(0.6, anim, { slide_y = 1 }, 'in-out-cubic')
        timer.tween(0.6, anim, { title_alpha = 1, title_y_offset = 0 }, 'out-cubic')
    end)
    
    -- PHASE 3: The Staggered Cascade (Version -> Maintainer -> Author)
    local cascade_start = 1.0 
    
    timer.after(cascade_start, function()
        timer.tween(0.5, anim, { version_alpha = 0.5, version_y_offset = 0 }, 'out-quad')
    end)
    
    timer.after(cascade_start + 0.1, function()
        timer.tween(0.5, anim, { maintainer_alpha = 0.5, maintainer_y_offset = 0 }, 'out-quad')
    end)
    
    timer.after(cascade_start + 0.2, function()
        timer.tween(0.5, anim, { author_alpha = 0.5, author_y_offset = 0 }, 'out-quad')
    end)

    -- EXIT PHASE: Randomized Liquid transition
    timer.after(delay + cascade_start + 0.5, function()
        local w, h = love.graphics.getDimensions()
        splash.is_revealing = true
        
        if anim.reveal_style == "wave" then
            anim.wave_1_x = w + 100
            anim.wave_2_x = w + 250
            timer.tween(0.8, anim, { wave_1_x = -150 }, 'in-out-sine')
            timer.after(0.15, function()
                timer.tween(0.8, anim, { wave_2_x = -150 }, 'in-out-sine', function()
                    splash.finished = true
                    splash.is_revealing = false
                end)
            end)
        elseif anim.reveal_style == "bubbles" then
            timer.tween(1.0, anim, { bubble_progress = 1 }, 'out-quad', function()
                splash.finished = true
                splash.is_revealing = false
            end)
        elseif anim.reveal_style == "droplet" then
            local h = love.graphics.getHeight()
            timer.tween(0.4, anim, { drop_y = h / 2 }, 'in-quad', function()
                timer.tween(0.8, anim, { impact_r = math.max(w, h) * 1.5 }, 'out-quad', function()
                    splash.finished = true
                    splash.is_revealing = false
                end)
            end)
        end
    end)
    
    refresh_texts()
end

function splash.draw()
    if splash.finished then
        return
    end
    local width, height = love.graphics.getDimensions()
    if width ~= last_w or height ~= last_h or not app_name then
        refresh_texts()
    end
    
    local half_logo_height = logo:getHeight() * 0.5
    local half_logo_width = logo:getWidth() * 0.5

    -- Global Fade out control
    local r, g, b = colors.main[1], colors.main[2], colors.main[3]

    if splash.is_revealing and anim.reveal_style == "wave" then
        love.graphics.stencil(function()
            local points = { 0, 0, 0, height }
            local segments = 40
            for i = segments, 0, -1 do
                local y = (i / segments) * height
                local wave_offset = math.sin(y * 0.03 + love.timer.getTime() * 8) * 30
                table.insert(points, anim.wave_1_x + wave_offset)
                table.insert(points, y)
            end
            love.graphics.polygon("fill", points)
        end, "replace", 1)
        love.graphics.setStencilTest("greater", 0)
        
        love.graphics.setColor(colors.background)
        love.graphics.rectangle("fill", 0, 0, width, height)
    elseif anim.reveal_style == "bubbles" and splash.is_revealing then
        love.graphics.clear(colors.background)
    elseif anim.reveal_style == "droplet" and splash.is_revealing and anim.impact_r > 0 then
        love.graphics.stencil(function()
            love.graphics.circle("fill", width / 2, height / 2, anim.impact_r)
        end, "replace", 1)
        love.graphics.setStencilTest("greater", 0)
        love.graphics.setColor(colors.background)
        love.graphics.rectangle("fill", 0, 0, width, height)
    else
        love.graphics.clear(colors.background)
    end

    love.graphics.push()
    love.graphics.translate(width * 0.5, height * 0.5)
    
    -- Draw Logo (Scale handled by pop_scale, Y sliding handled by slide_y + Buoyancy)
    local buoyancy = math.sin(love.timer.getTime() * 2) * 4
    love.graphics.setColor(r, g, b, anim.fade_out)
    love.graphics.draw(logo, 0, -anim.slide_y * half_logo_height + buoyancy, 0, anim.pop_scale, anim.pop_scale, half_logo_width, half_logo_height)
    
    -- Draw App Name (Title)
    love.graphics.setColor(r, g, b, anim.title_alpha * anim.fade_out)
    love.graphics.push()
    love.graphics.translate(0, half_logo_height)
    love.graphics.draw(app_name, -app_name:getWidth() * 0.5, -anim.slide_y * app_name:getHeight() + anim.title_y_offset)
    love.graphics.pop()
    
    -- Calculate Heights and Spacing for Credits Cascade
    love.graphics.push()
    love.graphics.translate(0, height * 0.5 - 20)
    local v_h = app_version_text:getHeight()
    local ca_h = credits_author:getHeight()
    local cm_h = credits_maintainer:getHeight()
    local spacing = math.max(6, math.floor(ca_h * 0.4))
    
    -- Base Y positions climbing upwards from the bottom
    local version_base_y = -v_h
    local maintainer_base_y = version_base_y - cm_h - spacing
    local author_base_y = maintainer_base_y - ca_h - spacing * 2

    -- Draw Version
    love.graphics.setColor(r, g, b, anim.version_alpha * anim.fade_out)
    love.graphics.draw(app_version_text, -app_version_text:getWidth() * 0.5, version_base_y + anim.version_y_offset)
    
    -- Draw Maintainer
    love.graphics.setColor(r, g, b, anim.maintainer_alpha * anim.fade_out)
    love.graphics.draw(credits_maintainer, -credits_maintainer:getWidth() * 0.5, maintainer_base_y + anim.maintainer_y_offset)
    
    -- Draw Author
    love.graphics.setColor(r, g, b, anim.author_alpha * anim.fade_out)
    love.graphics.draw(credits_author, -credits_author:getWidth() * 0.5, author_base_y + anim.author_y_offset)
    
    love.graphics.pop()
    
    love.graphics.setColor(colors.background)
    love.graphics.pop()

    if splash.is_revealing and anim.reveal_style == "wave" then
        love.graphics.setStencilTest()
        
        local points = {}
        local segments = 40
        for i = 0, segments do
            local y = (i / segments) * height
            local wave_offset = math.sin(y * 0.03 + love.timer.getTime() * 8) * 30
            table.insert(points, anim.wave_1_x + wave_offset)
            table.insert(points, y)
        end
        for i = segments, 0, -1 do
            local y = (i / segments) * height
            local wave_offset = math.sin(y * 0.035 + love.timer.getTime() * 7) * 40
            table.insert(points, anim.wave_2_x + wave_offset)
            table.insert(points, y)
        end
        
        local accent_color = theme:read_color("button", "BUTTON_FOCUS", "#cbaa0f")
        love.graphics.setColor(accent_color[1], accent_color[2], accent_color[3], 1)
        love.graphics.polygon("fill", points)
    end

    -- Draw Bubbles if active
    if anim.reveal_style == "bubbles" and splash.is_revealing then
        local accent_color = theme:read_color("button", "BUTTON_FOCUS", "#cbaa0f")
        love.graphics.setColor(accent_color[1], accent_color[2], accent_color[3], anim.bubble_progress * 2)
        local num_bubbles = 20
        for i = 1, num_bubbles do
            local bx = (i / num_bubbles) * width
            local seed = i * 123.45
            local by = height - (anim.bubble_progress * height * (1 + math.sin(seed) * 0.3))
            local br = 10 + math.abs(math.sin(seed * 2)) * 30
            love.graphics.circle("fill", bx, by, br * (1 - anim.bubble_progress))
        end
    end

    -- Draw Droplet/Impact if active
    if anim.reveal_style == "droplet" and splash.is_revealing then
        local accent_color = theme:read_color("button", "BUTTON_FOCUS", "#cbaa0f")
        if anim.impact_r == 0 then
            -- Falling drop
            love.graphics.setColor(accent_color)
            love.graphics.circle("fill", width / 2, anim.drop_y, 12)
            -- Trail
            love.graphics.setLineWidth(4)
            love.graphics.line(width / 2, anim.drop_y, width / 2, anim.drop_y - 20)
        else
            -- Expanding Impact ring
            love.graphics.setStencilTest()
            love.graphics.setColor(accent_color[1], accent_color[2], accent_color[3], 1 - (anim.impact_r / (math.max(width, height) * 1.5)))
            love.graphics.setLineWidth(10)
            love.graphics.circle("line", width / 2, height / 2, anim.impact_r)
        end
    end
end

function splash.finish()
    splash.finished = true
end

return splash
