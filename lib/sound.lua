local sound = {}

local sounds = {}

local function load_sfx(name, filename)
    if not love.audio then return end
    local path = "assets/sfx/" .. filename
    if love.filesystem.getInfo(path) then
        sounds[name] = love.audio.newSource(path, "static")
    end
end

function sound.init()
    load_sfx("nav_move", "navigate.wav")
    load_sfx("nav_confirm", "confirm.wav")
    load_sfx("nav_back", "back.wav")
    load_sfx("keypress", "keypress.wav")
    load_sfx("option", "option.wav")
end

function sound.play(name, pitch)
    if not love.audio then return end
    if sounds[name] then
        -- Stop if already playing to allow rapid repetition
        sounds[name]:stop()
        local p = pitch or 1.0
        if not pitch and name == "option" then
            p = 0.6
        end
        sounds[name]:setPitch(p)
        sounds[name]:play()
    end
end

return sound
