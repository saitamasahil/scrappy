require("globals")
local log = require("lib.log")
local pprint = require("lib.pprint")

local scenes = require("lib.scenes")
local skyscraper = require("lib.skyscraper")
local splash = require("lib.splash")

local configs = require("helpers.config")
local input = require("helpers.input")
local utils = require("helpers.utils")
local sound = require("lib.sound")

sound.init()

log.start()

local user_config, skyscraper_config = configs.user_config, configs.skyscraper_config
local theme = configs.theme

_G.MAIN_FONT_PATH = theme:read("main", "FONT") or "assets/Inter-Medium.ttf"
local base_font_size = theme:read_number("main", "FONT_SIZE") or 20
local font = nil

-- Global footer removed to avoid overlap; scenes now manage their own footers
local w_width, w_height = love.window.getMode()
update_ui_scale()

function love.load(args)
    math.randomseed(os.time())
    splash.load()

    if #args > 0 then
        local w, h = 640, 480
        if #args >= 2 then
            -- Handle "1920 1080" format
            w = tonumber(args[1]) or 640
            h = tonumber(args[2]) or 480
            _G.resolution = w .. "x" .. h
        else
            -- Handle "1920x1080" format
            local res = utils.split(args[1], "x")
            w = tonumber(res[1]) or 640
            h = tonumber(res[2]) or 480
            _G.resolution = args[1]
        end
        love.window.setMode(w, h)
        w_width, w_height = love.window.getMode()
        update_ui_scale()
    end

    font = love.graphics.newFont(_G.MAIN_FONT_PATH, math.floor(base_font_size * _G.scale))
    love.graphics.setFont(font)

    -- Debug mode
    local debug = user_config:read("main", "debug")
    if debug ~= "1" then
        _G.print = function()
        end
        setmetatable(pprint, {
            __call = function()
            end
        })
    end

    scenes:load("main")

    skyscraper.init(skyscraper_config.path, user_config:read("overrides", "binary") or "bin/Skyscraper.aarch64")
    input.load()

    -- footer:updatePosition(...) removed
end

function love.update(dt)
    -- Cap dt to 0.05 (20fps minimum) to prevent animations from glitching/exploding
    -- when the main thread blocks during heavy operations (like rebuilding long lists).
    dt = math.min(dt, 0.05)
    
    timer.update(dt)
    input.update(dt)
    scenes:update(dt)
    -- footer:update(dt) removed
    input.onEvent(function(key)
        scenes:keypressed(key)
    end)
    input.postUpdate()
end

function love.draw()

    if splash.finished or splash.is_revealing then
        scenes:draw()
        -- Draw footer on main scene; also on settings when no overlay (VK) is active
        -- Footers are now drawn by individual scenes to avoid overlap
        -- local focus = scenes:currentFocus()
        -- if focus == "main" or (focus == "settings" and not (_G.ui_overlay_active or false)) then
        --     footer:draw()
        -- end
    end

    if not splash.finished then
        splash.draw()
    end
end

-- Cleanup when app quits
function love.quit()
    -- Stop any background web servers started by Scrappy
    -- (Artwork Manager, Scrape Dashboard, TGDB key helper, etc.)
    os.execute("pkill -9 -f artwork_manager.py 2>/dev/null")
    os.execute("pkill -9 -f scrape_dashboard.py 2>/dev/null")
    os.execute("pkill -9 -f tgdb_server.py 2>/dev/null")
    os.execute("pkill -9 -f igdb_server.py 2>/dev/null")
    os.execute("pkill -9 -f template_maker.py 2>/dev/null")

    skyscraper.shutdown()
    return false -- Allow quit to proceed
end
