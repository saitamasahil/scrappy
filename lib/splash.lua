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
    reveal_style = "wave", -- wave | bubbles | droplet | rain
    bubble_progress = 0,
    drop_y = -100,
    impact_r = 0,
    rain_progress = 0,
    raindrops = {},
    ripples = {},
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
    anim.particles = {}
    
    local styles = { "wave", "bubbles", "droplet", "rain" }
    anim.reveal_style = styles[math.random(#styles)]
    
    if anim.reveal_style == "rain" then
        anim.raindrops = {}
        anim.ripples = {}
        anim.rain_time = 0
        local w, h = love.graphics.getDimensions()
        for i = 1, 30 do
            local seed = i * 555.55
            local target_x = (math.sin(seed) * 0.45 + 0.5) * w
            local target_y = (math.cos(seed * 1.3) * 0.45 + 0.5) * h
            
            local speed = 1600 + math.random(0, 500)
            
            table.insert(anim.raindrops, {
                target_x = target_x,
                target_y = target_y,
                x = target_x,
                y = -100,
                dx = 0,
                dy = speed,
                length = 35 + math.random(0, 20),
                speed = speed,
                delay = math.random() * 0.8,
                active = true,
                has_impacted = false,
                reveal_radius = 0
            })
        end
    end
    
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
            timer.tween(1.6, anim, { rain_progress = 1 }, 'linear', function()
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
                local segments = 60
                local t = love.timer.getTime()
                for i = segments, 0, -1 do
                    local y = (i / segments) * height
                    local sine = math.sin(y * 0.02 + t * 8)
                    local offset = (sine + 0.35 * math.sin(y * 0.05 - t * 4)) * 30
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
                -- Sweep persistent circular reveal holes for each impacted raindrop!
                for _, drop in ipairs(anim.raindrops) do
                    if drop.has_impacted and drop.reveal_radius > 0 then
                        love.graphics.circle("fill", drop.target_x, drop.target_y, drop.reveal_radius)
                    end
                end
                -- Fill remaining gaps at the end of the transition
                if anim.rain_time and anim.rain_time > 1.3 then
                    love.graphics.rectangle("fill", 0, 0, width, height * math.min(1, (anim.rain_time - 1.3) / 0.3))
                end
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
            local segments = 60
            local t = love.timer.getTime()

            -- ==========================================
            -- LAYER 1: Deep Back Wave (25% opacity, offset 120px to the right)
            -- ==========================================
            local points_back = {}
            for i = 0, segments do
                local y = (i / segments) * height
                local wave_offset = (math.sin(y * 0.01 + t * 4) + 0.3 * math.sin(y * 0.02 - t * 2)) * 60
                local wx = (width - anim.wave_1_x) + wave_offset + 120
                table.insert(points_back, wx)
                table.insert(points_back, y)
            end
            for i = segments, 0, -1 do
                local y = (i / segments) * height
                local wave_offset = (math.sin(y * 0.01 + t * 4) + 0.3 * math.sin(y * 0.02 - t * 2)) * 60
                local wx = (width - anim.wave_1_x) + wave_offset + 420
                table.insert(points_back, wx)
                table.insert(points_back, y)
            end
            love.graphics.setColor(accent_color[1] * 0.8, accent_color[2] * 0.8, accent_color[3] * 0.8, 0.25)
            love.graphics.polygon("fill", points_back)

            -- ==========================================
            -- LAYER 2: Middle Wave (55% opacity, offset 50px to the right)
            -- ==========================================
            local points_mid = {}
            for i = 0, segments do
                local y = (i / segments) * height
                local wave_offset = (math.sin(y * 0.015 + t * 6) + 0.4 * math.sin(y * 0.03 + t * 3)) * 45
                local wx = (width - anim.wave_1_x) + wave_offset + 50
                table.insert(points_mid, wx)
                table.insert(points_mid, y)
            end
            for i = segments, 0, -1 do
                local y = (i / segments) * height
                local wave_offset = (math.sin(y * 0.015 + t * 6) + 0.4 * math.sin(y * 0.03 + t * 3)) * 45
                local wx = (width - anim.wave_1_x) + wave_offset + 300
                table.insert(points_mid, wx)
                table.insert(points_mid, y)
            end
            love.graphics.setColor(accent_color[1], accent_color[2], accent_color[3], 0.55)
            love.graphics.polygon("fill", points_mid)

            -- ==========================================
            -- LAYER 3: Main Front Wave (100% opacity, base sweep line)
            -- ==========================================
            local points_front = {}
            local foam_points = {}
            for i = 0, segments do
                local y = (i / segments) * height
                local wave_offset = (math.sin(y * 0.02 + t * 8) + 0.35 * math.sin(y * 0.05 - t * 4)) * 30
                local wx = (width - anim.wave_1_x) + wave_offset
                table.insert(points_front, wx)
                table.insert(points_front, y)
                table.insert(foam_points, wx)
                table.insert(foam_points, y)
            end
            for i = segments, 0, -1 do
                local y = (i / segments) * height
                local wave_offset = (math.sin(y * 0.02 + t * 8) + 0.35 * math.sin(y * 0.05 - t * 4)) * 30
                local wx = (width - anim.wave_1_x) + wave_offset + 180
                table.insert(points_front, wx)
                table.insert(points_front, y)
            end
            love.graphics.setColor(math.min(1, accent_color[1] * 1.1), math.min(1, accent_color[2] * 1.1), math.min(1, accent_color[3] * 1.1), 1.0)
            love.graphics.polygon("fill", points_front)

            -- ==========================================
            -- LAYER 4: Dynamic Foaming leading Crest & Trails
            -- ==========================================
            -- 1. Draw gapless white backing line
            love.graphics.setColor(0.96, 0.95, 0.91, 0.95)
            love.graphics.setLineWidth(2)
            love.graphics.line(foam_points)

            -- 2. Draw Soft Foam Fizz Backing (Outer pass, semi-transparent)
            for i = 0, segments do
                local y = (i / segments) * height
                local sine = math.sin(y * 0.02 + t * 8)
                local wave_offset = (sine + 0.35 * math.sin(y * 0.05 - t * 4)) * 30
                local wx = (width - anim.wave_1_x) + wave_offset
                
                local foam_r = 1.5 + math.max(0, sine) * 6.5
                love.graphics.setColor(0.96, 0.95, 0.91, 0.3)
                love.graphics.circle("fill", wx, y, foam_r * 1.5)
            end
            
            -- 3. Draw Solid Dense Foam Core (Inner pass, fully opaque)
            for i = 0, segments do
                local y = (i / segments) * height
                local sine = math.sin(y * 0.02 + t * 8)
                local wave_offset = (sine + 0.35 * math.sin(y * 0.05 - t * 4)) * 30
                local wx = (width - anim.wave_1_x) + wave_offset
                
                local foam_r = 1.5 + math.max(0, sine) * 6.5
                love.graphics.setColor(0.96, 0.95, 0.91, 0.95)
                love.graphics.circle("fill", wx, y, foam_r)
            end

            -- 4. Draw & Update Trailing Foam Bubbles (Dynamic 3D particles)
            local dt = love.timer.getDelta()
            
            -- Spawn new foam particles at random points along the wave front
            if splash.is_revealing and math.random() < 0.6 then
                for _ = 1, 4 do
                    local py_ratio = math.random()
                    local py = py_ratio * height
                    local sine = math.sin(py * 0.02 + t * 8)
                    local wave_offset = (sine + 0.35 * math.sin(py * 0.05 - t * 4)) * 30
                    local px = (width - anim.wave_1_x) + wave_offset
                    
                    table.insert(anim.particles, {
                        x = px,
                        y = py,
                        vx = math.random(-180, -60), -- Float backward relative to the right-moving wave
                        vy = math.random(-25, 25),
                        life = 1.0,
                        size = math.random(3, 8)
                    })
                end
            end
            
            -- Render and update foam particles
            for i = #anim.particles, 1, -1 do
                local p = anim.particles[i]
                p.x = p.x + p.vx * dt
                p.y = p.y + p.vy * dt
                p.life = p.life - dt * 2.0 -- dissolve in 0.5s
                
                if p.life <= 0 then
                    table.remove(anim.particles, i)
                else
                    -- Draw foam bubble with a soft glow
                    love.graphics.setColor(0.96, 0.95, 0.91, p.life * 0.7)
                    love.graphics.circle("fill", p.x, p.y, p.size * p.life)
                    
                    -- Draw inner highlight for 3D bubble effect
                    love.graphics.setColor(1, 1, 1, p.life * 0.9)
                    love.graphics.circle("fill", p.x - p.size * 0.25 * p.life, p.y - p.size * 0.25 * p.life, p.size * 0.25 * p.life)
                end
            end
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
                -- 1. Elastic stretching/wobbling teardrop shape based on speed
                local t = love.timer.getTime()
                local wobble = math.sin(t * 22) * 0.08
                local w_scale = 1.0 - wobble
                local h_scale = 1.0 + wobble + 0.25 -- elongated falling shape
                
                love.graphics.push()
                love.graphics.translate(width / 2, anim.drop_y)
                love.graphics.scale(w_scale, h_scale)
                
                -- Draw main teardrop body
                love.graphics.setColor(accent_color[1], accent_color[2], accent_color[3], 1)
                love.graphics.circle("fill", 0, 0, 15)
                love.graphics.polygon("fill", -14, -2, 14, -2, 0, -45)
                
                -- Draw beautiful glowing 3D specular water highlight (3D liquid look)
                love.graphics.setColor(1, 1, 1, 0.85)
                love.graphics.circle("fill", -5, -8, 3)
                love.graphics.circle("fill", -3, -12, 1.5)
                
                love.graphics.pop()
                    
                -- 2. Beautiful gradient motion trail fading out behind the drop
                for i = 1, 8 do
                    local alpha = 0.5 * (1 - (i / 8))
                    love.graphics.setColor(accent_color[1], accent_color[2], accent_color[3], alpha)
                    love.graphics.setLineWidth(4 - (i * 0.3))
                    love.graphics.line(
                        width / 2, anim.drop_y - 45 - (i - 1) * 11,
                        width / 2, anim.drop_y - 45 - i * 11
                    )
                end
            else
                local alpha = 1 - (anim.impact_r / (math.max(width, height) * 1.5))
                love.graphics.setColor(accent_color[1], accent_color[2], accent_color[3], alpha)
                
                -- Double echo ring for impact
                love.graphics.setLineWidth(12)
                love.graphics.circle("line", width / 2, height / 2, anim.impact_r)
                
                love.graphics.setColor(accent_color[1], accent_color[2], accent_color[3], alpha * 0.4)
                love.graphics.setLineWidth(4)
                love.graphics.circle("line", width / 2, height / 2, anim.impact_r * 0.8)
                
                -- Update and draw splash particles with glistening white highlight cores
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
                        -- Solid accent droplet color
                        love.graphics.setColor(accent_color[1], accent_color[2], accent_color[3], p.life)
                        love.graphics.circle("fill", p.x, p.y, 4)
                        
                        -- Glistening specular white core (makes particles look like liquid droplets)
                        love.graphics.setColor(1, 1, 1, p.life * 0.85)
                        love.graphics.circle("fill", p.x - 1, p.y - 1, 1.5)
                        
                        -- Motion trails for the splash particles
                        love.graphics.setColor(accent_color[1], accent_color[2], accent_color[3], p.life * 0.5)
                        love.graphics.setLineWidth(2)
                        love.graphics.line(p.x, p.y, p.x - p.vx * dt * 2, p.y - p.vy * dt * 2)
                end
            end
        end
    elseif anim.reveal_style == "rain" then
            local dt = love.timer.getDelta()
            
            -- Accumulate time during reveal
            if not anim.rain_time then
                anim.rain_time = 0
            end
            anim.rain_time = anim.rain_time + dt

            -- 1. PHYSICS: Update raindrops, ripples, and gravity particles
            for _, drop in ipairs(anim.raindrops) do
                if drop.active and anim.rain_time >= drop.delay then
                    drop.x = drop.x + drop.dx * dt
                    drop.y = drop.y + drop.dy * dt
                    
                    -- Handle screen impact
                    if drop.y >= drop.target_y then
                        drop.active = false
                        drop.has_impacted = true
                        
                        -- Spawn Circular Ripple
                        table.insert(anim.ripples, {
                            x = drop.target_x,
                            y = drop.target_y,
                            radius = 0,
                            max_radius = 160 + math.random(0, 80),
                            life = 1.0,
                            speed = 280 + math.random(0, 110)
                        })
                        
                        -- Spawn Propelled Crown Splash Particles (Symmetric left/right)
                        for k = 1, 8 do
                            local p_angle = math.rad(math.random(-140, -40))
                            local p_speed = 180 + math.random(0, 160)
                            table.insert(anim.particles, {
                                x = drop.target_x,
                                y = drop.target_y,
                                vx = math.cos(p_angle) * p_speed, -- symmetric vertical splash
                                vy = math.sin(p_angle) * p_speed,
                                life = 1.0,
                                size = 2 + math.random() * 2
                            })
                        end
                    end
                elseif drop.has_impacted then
                    -- Grow reveal radius persistently
                    drop.reveal_radius = drop.reveal_radius + 320 * dt
                end
            end

            -- Update active ripples
            for i = #anim.ripples, 1, -1 do
                local rip = anim.ripples[i]
                rip.radius = rip.radius + rip.speed * dt
                rip.life = 1.0 - (rip.radius / rip.max_radius)
                if rip.life <= 0 then
                    table.remove(anim.ripples, i)
                end
            end

            -- Update splash particles under gravity
            for i = #anim.particles, 1, -1 do
                local p = anim.particles[i]
                p.x = p.x + p.vx * dt
                p.y = p.y + p.vy * dt
                p.vy = p.vy + 750 * dt -- gravity downward acceleration
                p.life = p.life - dt * 2.2 -- dissolve in ~0.45s
                if p.life <= 0 then
                    table.remove(anim.particles, i)
                end
            end

            -- 2. DRAWING: Render falling streaks, ripples, and glistening drops
            -- Draw raindrops (straight vertical lines)
            love.graphics.setLineWidth(1.5)
            for _, drop in ipairs(anim.raindrops) do
                if drop.active and anim.rain_time >= drop.delay then
                    love.graphics.setColor(accent_color[1], accent_color[2], accent_color[3], 0.75)
                    love.graphics.line(drop.x, drop.y, drop.x, drop.y - drop.length)
                end
            end

            -- Draw expanding circular ripples (original style)
            for _, rip in ipairs(anim.ripples) do
                if rip.life > 0 then
                    -- Main Outer Ripple Ring
                    love.graphics.setColor(accent_color[1], accent_color[2], accent_color[3], rip.life * 0.75)
                    love.graphics.setLineWidth(2)
                    love.graphics.circle("line", rip.x, rip.y, rip.radius)
                    
                    -- Inner Echo Ripple Ring
                    if rip.radius > 20 then
                        love.graphics.setColor(accent_color[1], accent_color[2], accent_color[3], rip.life * 0.35)
                        love.graphics.circle("line", rip.x, rip.y, rip.radius - 20)
                    end
                end
            end

            -- Draw glistening micro-splash droplets
            for _, p in ipairs(anim.particles) do
                -- Soft splash color body
                love.graphics.setColor(accent_color[1], accent_color[2], accent_color[3], p.life * 0.8)
                love.graphics.circle("fill", p.x, p.y, p.size * p.life)
                
                -- Specs of light (3D glistening highlights)
                love.graphics.setColor(1, 1, 1, p.life * 0.95)
                love.graphics.circle("fill", p.x - p.size * 0.25 * p.life, p.y - p.size * 0.25 * p.life, p.size * 0.25 * p.life)
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
