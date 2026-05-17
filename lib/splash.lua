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

-- SFX loading system
local sounds = {}
local function load_sfx(name, filename)
    if not love.audio then return end
    local path = "assets/sfx/" .. filename
    if love.filesystem.getInfo(path) then
        sounds[name] = love.audio.newSource(path, "static")
    end
end

local function play_sfx(name)
    local sound_module = require("lib.sound")
    if not sound_module.enabled or not love.audio then return end
    if sounds[name] then
        sounds[name]:stop()
        sounds[name]:play()
    end
end

load_sfx("logo", "logo_pop.wav")

local function refresh_texts()
    local w, h = love.graphics.getDimensions()
    last_w, last_h = w, h
    -- Font sizes scale with height; clamp to sensible min/max for handhelds
    local title_size = math.max(18, math.min(96, math.floor(h * 0.10)))
    local sub_size = math.max(12, math.min(48, math.floor(h * 0.035)))

    local title_font = love.graphics.newFont(_G.MAIN_FONT_PATH or title_size, title_size)
    local sub_font = love.graphics.newFont(_G.MAIN_FONT_PATH or sub_size, sub_size)
    credits_font = love.graphics.newFont(_G.MAIN_FONT_PATH or (sub_size + 2), sub_size + 2) -- slight increase for credits

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
    title_y_offset = 20 * _G.scale,
    version_alpha = 0,     -- Phase 3: Cascade
    version_y_offset = 20 * _G.scale,
    maintainer_alpha = 0,
    maintainer_y_offset = 20 * _G.scale,
    author_alpha = 0,
    author_y_offset = 20 * _G.scale,
    fade_out = 1,          -- Final sequence to exit
    wave_1_x = 0,
    wave_2_x = 0,
    reveal_style = "wave", -- wave | bubbles | droplet | rain | tidal
    bubble_progress = 0,
    drop_y = -100,
    impact_r = 0,
    rain_progress = 0,
    waterfall_progress = 0,
    particles = {}         -- for droplet impact
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
    anim.wave_1_x = 0
    anim.wave_2_x = 0
    anim.bubble_progress = 0
    anim.drop_y = -100
    anim.impact_r = 0
    anim.vortex_rot = 0
    anim.vortex_scale = 0
    anim.rain_progress = 0
    anim.waterfall_progress = 0
    anim.tidal_y = 0
    anim.particles = {}
    
    local styles = { "wave", "bubbles", "droplet", "rain", "waterfall" }
    anim.reveal_style = styles[math.random(#styles)]
    
    splash.finished = false
    splash.is_revealing = false

    -- PHASE 1: Logo Pop-In (Elastic/Bouncy)
    timer.after(0.3, function()
        play_sfx("logo")
        timer.tween(0.8, anim, { pop_scale = 1.0 }, 'out-elastic')
    end)

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
                -- Spawn particles
                for i = 1, 40 do
                    local angle = math.random() * math.pi * 2
                    local speed = 200 + math.random() * 400
                    table.insert(anim.particles, {
                        x = w / 2,
                        y = h / 2,
                        vx = math.cos(angle) * speed,
                        vy = math.sin(angle) * speed,
                        life = 1.0
                    })
                end
                timer.tween(0.8, anim, { impact_r = math.max(w, h) * 1.5 }, 'out-quad', function()
                    splash.finished = true
                    splash.is_revealing = false
                end)
            end)
        elseif anim.reveal_style == "rain" then
            timer.tween(1.2, anim, { rain_progress = 1 }, 'linear', function()
                splash.finished = true
                splash.is_revealing = false
            end)
        elseif anim.reveal_style == "waterfall" then
            timer.tween(1.0, anim, { waterfall_progress = 1 }, 'in-quad', function()
                splash.finished = true
                splash.is_revealing = false
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
    
    local half_logo_height = (logo:getHeight() * 0.5) * _G.scale
    local half_logo_width = (logo:getWidth() * 0.5) * _G.scale

    -- Global Fade out control
    local r, g, b = colors.main[1], colors.main[2], colors.main[3]

    if splash.is_revealing then
        -- REVEAL LOGIC: Cover the screen and use stencils to POKE HOLES to reveal the UI
        love.graphics.stencil(function()
            if anim.reveal_style == "wave" then
                -- Sweep from left to right to reveal
                local points = { 0, 0, 0, height }
                local segments = 40
                for i = segments, 0, -1 do
                    local y = (i / segments) * height
                    local offset = math.sin(y * 0.03 + love.timer.getTime() * 8) * 30
                    table.insert(points, (width - anim.wave_1_x) + offset)
                    table.insert(points, y)
                end
                love.graphics.polygon("fill", points)
            elseif anim.reveal_style == "bubbles" then
                -- Grow bubbles to reveal
                local num_bubbles = 30
                local t = love.timer.getTime()
                for i = 1, num_bubbles do
                    -- Slight horizontal drift based on time
                    local seed = i * 123.45
                    local drift_x = math.sin(t * 3 + seed) * 30
                    local bx = ((i - 0.5) / num_bubbles) * width + drift_x
                    
                    local speed_mult = 1 + math.sin(seed) * 0.5
                    local by = height - (anim.bubble_progress * height * speed_mult) + 50
                    
                    local base_r = 15 + math.abs(math.sin(seed * 2)) * 80
                    local current_r = base_r * (anim.bubble_progress * 2)
                    
                    if current_r > 0 then
                        -- Wobble effect: slight variance in rx and ry
                        local wobble_x = 1 + math.sin(t * 8 + seed) * 0.1
                        local wobble_y = 1 + math.cos(t * 8 + seed) * 0.1
                        love.graphics.ellipse("fill", bx, by, current_r * wobble_x, current_r * wobble_y)
                    end
                end
                if anim.bubble_progress > 0.8 then
                    love.graphics.rectangle("fill", 0, height * (1 - (anim.bubble_progress - 0.8) * 5), width, height)
                end
            elseif anim.reveal_style == "droplet" and anim.impact_r > 0 then
                love.graphics.circle("fill", width / 2, height / 2, anim.impact_r)
            elseif anim.reveal_style == "rain" then
                for i = 1, 30 do
                    local seed = i * 555.55
                    local rx = (math.sin(seed) * 0.5 + 0.5) * width
                    local ry = (math.cos(seed * 1.2) * 0.5 + 0.5) * height
                    local r_max = 250
                    local r_progress = math.max(0, math.min(1, (anim.rain_progress * 1.5) - (i * 0.02)))
                    if r_progress > 0 then
                        love.graphics.circle("fill", rx, ry, r_progress * r_max)
                    end
                end
                if anim.rain_progress > 0.8 then
                   love.graphics.rectangle("fill", 0, 0, width, height * (anim.rain_progress - 0.8) * 5)
                end
            elseif anim.reveal_style == "waterfall" then
                -- The reveal mask is just the falling rectangle
                love.graphics.rectangle("fill", 0, 0, width, height * anim.waterfall_progress)
            end
        end, "replace", 1)

        -- Draw the MASK color where stencil is 0 (not revealed yet)
        love.graphics.setStencilTest("equal", 0)
        love.graphics.setColor(colors.background)
        love.graphics.rectangle("fill", 0, 0, width, height)
        love.graphics.setStencilTest()

        -- Draw the Accent-Colored "Water" effects over the reveal
        local accent_color = theme:read_color("button", "BUTTON_FOCUS", "#cbaa0f")
        if anim.reveal_style == "wave" then
            local points = {}
            local segments = 40
            for i = 0, segments do
                local y = (i / segments) * height
                local wave_offset = math.sin(y * 0.03 + love.timer.getTime() * 8) * 30
                table.insert(points, (width - anim.wave_1_x) + wave_offset)
                table.insert(points, y)
            end
            for i = segments, 0, -1 do
                local y = (i / segments) * height
                local wave_offset = math.sin(y * 0.035 + love.timer.getTime() * 7) * 40
                table.insert(points, (width - anim.wave_1_x) + 150 + wave_offset)
                table.insert(points, y)
            end
            love.graphics.setColor(accent_color[1], accent_color[2], accent_color[3], 1)
            love.graphics.polygon("fill", points)
        elseif anim.reveal_style == "bubbles" then
            local t = love.timer.getTime()
            local num_bubbles = 30
            for i = 1, num_bubbles do
                local seed = i * 123.45
                local drift_x = math.sin(t * 3 + seed) * 30
                local bx = ((i - 0.5) / num_bubbles) * width + drift_x
                
                local speed_mult = 1 + math.sin(seed) * 0.5
                local by = height - (anim.bubble_progress * height * speed_mult) + 50
                
                local base_r = 15 + math.abs(math.sin(seed * 2)) * 80
                
                -- Accent bubbles (these pop/fade out)
                local pop_r = base_r * (1 - anim.bubble_progress)
                if pop_r > 0 then
                    local wobble_x = 1 + math.sin(t * 8 + seed) * 0.1
                    local wobble_y = 1 + math.cos(t * 8 + seed) * 0.1
                    local rx, ry = pop_r * wobble_x, pop_r * wobble_y
                    
                    -- Main bubble body
                    love.graphics.setColor(accent_color[1], accent_color[2], accent_color[3], anim.bubble_progress * 1.5)
                    love.graphics.ellipse("fill", bx, by, rx, ry)
                    
                    -- Bubble outline for a soap-bubble feel
                    love.graphics.setColor(accent_color[1], accent_color[2], accent_color[3], anim.bubble_progress * 2.5)
                    love.graphics.setLineWidth(2)
                    love.graphics.ellipse("line", bx, by, rx, ry)
                    
                    -- Specular highlight (white reflection spot)
                    if rx > 5 then
                        love.graphics.setColor(1, 1, 1, anim.bubble_progress * 2.0)
                        love.graphics.ellipse("fill", bx + rx * 0.3, by - ry * 0.4, rx * 0.2, ry * 0.1)
                    end
                end
            end
        elseif anim.reveal_style == "droplet" then
            if anim.impact_r == 0 then
                -- Draw an elongated teardrop shape
                love.graphics.setColor(accent_color[1], accent_color[2], accent_color[3], 1)
                love.graphics.circle("fill", width / 2, anim.drop_y, 15)
                
                -- Triangle tail to make it look like a teardrop
                love.graphics.polygon("fill", 
                    width / 2 - 14, anim.drop_y - 2, 
                    width / 2 + 14, anim.drop_y - 2, 
                    width / 2, anim.drop_y - 45)
                    
                -- Streak trail behind it
                love.graphics.setColor(accent_color[1], accent_color[2], accent_color[3], 0.5)
                love.graphics.setLineWidth(4)
                love.graphics.line(width / 2, anim.drop_y - 40, width / 2, anim.drop_y - 120)
            else
                local alpha = 1 - (anim.impact_r / (math.max(width, height) * 1.5))
                love.graphics.setColor(accent_color[1], accent_color[2], accent_color[3], alpha)
                
                -- Double echo ring for impact
                love.graphics.setLineWidth(12)
                love.graphics.circle("line", width / 2, height / 2, anim.impact_r)
                
                love.graphics.setColor(accent_color[1], accent_color[2], accent_color[3], alpha * 0.4)
                love.graphics.setLineWidth(4)
                love.graphics.circle("line", width / 2, height / 2, anim.impact_r * 0.8)
                
                local dt = love.timer.getDelta()
                for i = #anim.particles, 1, -1 do
                    local p = anim.particles[i]
                    p.x = p.x + p.vx * dt
                    p.y = p.y + p.vy * dt
                    p.vy = p.vy + 800 * dt -- gravity pulling them down faster
                    p.life = p.life - dt * 1.5
                    if p.life <= 0 then
                        table.remove(anim.particles, i)
                    else
                        love.graphics.setColor(accent_color[1], accent_color[2], accent_color[3], p.life)
                        love.graphics.circle("fill", p.x, p.y, 4)
                        
                        -- Motion trails for the splash particles
                        love.graphics.setLineWidth(2)
                        love.graphics.line(p.x, p.y, p.x - p.vx * dt * 2, p.y - p.vy * dt * 2)
                    end
                end
            end
        elseif anim.reveal_style == "rain" then
            local t = love.timer.getTime()
            for i = 1, 30 do
                local seed = i * 555.55
                local rx = (math.sin(seed) * 0.5 + 0.5) * width
                local ry = (math.cos(seed * 1.2) * 0.5 + 0.5) * height
                local r_max = 200
                
                -- The ripple expansion progress
                local r_progress = math.max(0, math.min(1, (anim.rain_progress * 1.5) - (i * 0.02)))
                

                -- 2. Draw expanding double-echo ripple
                if r_progress > 0 and r_progress < 1 then
                    local alpha = 1 - r_progress
                    
                    -- Main ring
                    love.graphics.setColor(accent_color[1], accent_color[2], accent_color[3], alpha)
                    love.graphics.setLineWidth(2)
                    love.graphics.circle("line", rx, ry, r_progress * r_max)
                    
                    -- Inner echo ring
                    if r_progress > 0.1 then
                        love.graphics.setColor(accent_color[1], accent_color[2], accent_color[3], alpha * 0.5)
                        love.graphics.circle("line", rx, ry, (r_progress - 0.1) * r_max)
                    end
                end
            end
        elseif anim.reveal_style == "waterfall" then
            local fall_y = height * anim.waterfall_progress
            if fall_y > 0 and anim.waterfall_progress < 1 then
                local t = love.timer.getTime()
                
                -- Layer 1: Faint, fast background layer
                local p1 = {0, 0, width, 0}
                local segments = 40
                for i = segments, 0, -1 do
                    local x = (i / segments) * width
                    local wave = math.sin(x * 0.04 + t * 25) * 40
                    table.insert(p1, x)
                    table.insert(p1, fall_y + wave + 50)
                end
                love.graphics.setColor(accent_color[1], accent_color[2], accent_color[3], 0.3)
                love.graphics.polygon("fill", p1)

                -- Layer 2: Medium layer
                local p2 = {0, 0, width, 0}
                for i = segments, 0, -1 do
                    local x = (i / segments) * width
                    local wave = math.sin(x * 0.06 + t * 18) * 35
                    table.insert(p2, x)
                    table.insert(p2, fall_y + wave + 20)
                end
                love.graphics.setColor(accent_color[1], accent_color[2], accent_color[3], 0.6)
                love.graphics.polygon("fill", p2)

                -- Layer 3: Main solid layer
                local p3 = {0, 0, width, 0}
                for i = segments, 0, -1 do
                    local x = (i / segments) * width
                    local wave = math.sin(x * 0.05 + t * 20) * 30
                    table.insert(p3, x)
                    table.insert(p3, fall_y + wave)
                end
                love.graphics.setColor(accent_color[1], accent_color[2], accent_color[3], 1)
                love.graphics.polygon("fill", p3)
                
                -- Dynamic Droplets (streaks)
                for i = 1, 30 do
                    local seed = i * 13.5
                    local drop_x = (math.sin(seed) * 0.5 + 0.5) * width
                    -- Different falling speeds
                    local speed = 1000 + math.fmod(seed * 50, 800)
                    
                    -- Let droplets fall across the entire screen height independently
                    local drop_y = math.fmod(seed * 100 + t * speed, height + 100) - 50
                    
                    -- Only draw droplets that are ahead of the waterfall (with a small overlap margin)
                    if drop_y < height and drop_y > fall_y - 20 then
                        -- Streaks fade out at the top
                        local length = 15 + math.fmod(seed, 25)
                        local thickness = 1 + math.fmod(seed, 3)
                        love.graphics.setLineWidth(thickness)
                        love.graphics.setColor(accent_color[1], accent_color[2], accent_color[3], 0.8)
                        love.graphics.line(drop_x, drop_y, drop_x, drop_y + length)
                        
                        -- Add a circular "head" to the drop
                        love.graphics.setColor(accent_color[1], accent_color[2], accent_color[3], 1)
                        love.graphics.circle("fill", drop_x, drop_y + length, thickness)
                    end
                end
            end
        end
    else
        love.graphics.clear(colors.background)
    end

    if not splash.is_revealing then
        love.graphics.push()
        love.graphics.translate(width * 0.5, height * 0.5)

        -- Draw Logo (Scale handled by pop_scale, Y sliding handled by slide_y + Buoyancy)
        local buoyancy = math.sin(love.timer.getTime() * 2) * 4
        love.graphics.setColor(r, g, b, anim.fade_out)
        love.graphics.draw(logo, 0, -anim.slide_y * half_logo_height + buoyancy, 0, anim.pop_scale * _G.scale, anim.pop_scale * _G.scale, logo:getWidth() * 0.5,
            logo:getHeight() * 0.5)

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
        love.graphics.pop()
    end
end

function splash.finish()
    splash.finished = true
end

return splash
