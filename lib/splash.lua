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
    fade_out = 1           -- Final sequence to exit
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
    splash.finished = false

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

    -- EXIT PHASE: Fade out entirely to game
    timer.after(delay + cascade_start + 0.5, function()
        timer.tween(0.5, anim, { fade_out = 0 }, 'in-out-cubic', function()
            splash.finished = true
        end)
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

    love.graphics.clear(colors.background)

    love.graphics.push()
    love.graphics.translate(width * 0.5, height * 0.5)
    
    -- Draw Logo (Scale handled by pop_scale, Y sliding handled by slide_y)
    love.graphics.setColor(r, g, b, anim.fade_out)
    love.graphics.draw(logo, 0, -anim.slide_y * half_logo_height, 0, anim.pop_scale, anim.pop_scale, half_logo_width, half_logo_height)
    
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
end

function splash.finish()
    splash.finished = true
end

return splash
