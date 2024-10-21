_G.love.graphics.setDefaultFilter("nearest", "nearest")
_G.nativefs = require("lib.nativefs")
local parser = require("lib.parser")
_G.skyscraper = require("lib.skyscraper")
_G.work_dir = nativefs.getWorkingDirectory()


local timer = 0 -- A timer used to animate our circle.
local output = ""

local game = {
  index = 0,
  total = 0,
  title = "N/A",
}

function load_image(filename)
  local nfs = require("lib.nativefs") -- require from wherever you've put the nativefs.lua
  local file_data = nfs.newFileData(filename)
  if file_data then
    local image_data = love.image.newImageData(file_data)
    if image_data then
      return love.graphics.newImage(image_data)
    end
  end
end

_G.artworks = { "artwork", "retro-dither-logo" }
-- _G.artworks = { "retro-dither-logo", "retro-dither", "simple-box-cart" }
_G.current_artwork = 2

function love.load()
  cover = load_image("sample/media/covers/fake-rom.png")
  skyscraper.init("config.ini")
end

function love.update(dt)
  timer = timer + dt
end

function love.draw()
  love.graphics.draw(cover, 0, 0, 0, 0.5, 0.5)
  love.graphics.rectangle("line", 0, 0, 640 / 2, 480 / 2)
  love.graphics.print(artworks[current_artwork], 0, 0)
  love.graphics.circle('line', 100 + math.sin(timer) * 20, 100 + math.cos(timer) * 20, 20)
  local t = love.thread.getChannel("skyscraper-output"):pop()
  if t then
    game = parser.string_to_table(t)
  end
  -- love.graphics.print(game.title, 10, 10)
  love.graphics.rectangle("line", 10, 20, 100, 20)
  love.graphics.rectangle("fill", 10, 20, 100 * game.index / game.total, 20)
  love.graphics.print("Current game: " .. game.title, 10, 40)
end

function love.keypressed(key)
  if key == "escape" then
    love.event.quit()
  end

  if key == "space" then
    current_artwork = current_artwork + 1
    if current_artwork > #artworks then
      current_artwork = 1
    end

    local flags = "unattend"
    local sample_path = work_dir .. "/sample"
    local artwork_path = work_dir .. "/templates/" .. artworks[current_artwork] .. ".xml"

    -- local command = "./Skyscraper -p megadrive -d " ..
    --     sample_path .. " -i " .. sample_path .. " -a " .. artwork_path .. " --flags " .. flags

    -- prep
    -- local command = "./Skyscraper -p snes -c " .. work_dir .. "/config.ini"

    skyscraper.change_artwork(artwork_path)
    skyscraper.update_sample(artwork_path)
    -- skyscraper.update_artwork("snes", artwork_path)
    -- local handle = io.popen(command)
    -- if handle == nil then
    --   return
    -- end
    -- local result = handle:read("*a")
    -- handle:close()
    -- print(result)

    cover = load_image("sample/media/covers/fake-rom.png")
  end
end
