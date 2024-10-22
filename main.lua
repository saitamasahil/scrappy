require("consts")

love.graphics.setDefaultFilter("nearest", "nearest")
local skyscraper = require("lib.skyscraper")

local artworks = { "artwork", "retro-dither-logo" }
local current_artwork = 1

local timer = 0 -- A timer used to animate our circle.
local cover_preview = nil

local data = {
  index = 0,
  total = 0,
  title = "N/A",
}
local error = ""
local reload_preview = false

local function load_image(filename)
  local file_data = nativefs.newFileData(filename)
  if file_data then
    local image_data = love.image.newImageData(file_data)
    if image_data then
      return love.graphics.newImage(image_data)
    end
  end
end

function love.load()
  cover_preview = load_image("sample/media/covers/fake-rom.png")
  skyscraper.init("config.ini")
end

function love.update(dt)
  timer = timer + dt
end

function love.draw()
  if cover_preview then
    love.graphics.draw(cover_preview, 0, 0, 0, 0.5, 0.5)
  end
  love.graphics.rectangle("line", 0, 0, 640 / 2, 480 / 2)
  love.graphics.print(artworks[current_artwork], 0, 0)
  love.graphics.rectangle('fill', 10, 25 + math.sin(timer * 10) * 5, 4, 10)
  local t = OUTPUT_CHANNEL:pop()
  if t then
    if t.error ~= "" then
      error = t.error
    elseif next(t.data) ~= nil then
      data = t.data
      if reload_preview and t.data.title == "fake-rom" then
        cover_preview = load_image("sample/media/covers/fake-rom.png")
        reload_preview = false
      end
    end
  end

  love.graphics.rectangle("line", 10, 20, 100, 20)
  love.graphics.rectangle("fill", 10, 20, 100 * data.index / data.total, 20)
  love.graphics.print("Current data: " .. data.title, 10, 40)
  if error ~= "" then
    love.graphics.print("ERROR: " .. error, 10, 40)
  end
end

function love.keypressed(key)
  if key == "escape" then
    love.event.quit()
  end

  if key == "left" then
    current_artwork = current_artwork - 1
    if current_artwork < 1 then
      current_artwork = #artworks
    end
    local sample_artwork = WORK_DIR .. "/templates/" .. artworks[current_artwork] .. ".xml"
    skyscraper.change_artwork(sample_artwork)
    skyscraper.update_sample(sample_artwork)
    reload_preview = true
  end

  if key == "right" then
    current_artwork = current_artwork + 1
    if current_artwork > #artworks then
      current_artwork = 1
    end
    local sample_artwork = WORK_DIR .. "/templates/" .. artworks[current_artwork] .. ".xml"
    skyscraper.change_artwork(sample_artwork)
    skyscraper.update_sample(sample_artwork)
    reload_preview = true
  end

  if key == "space" then
    local sample_artwork = WORK_DIR .. "/templates/" .. artworks[current_artwork] .. ".xml"
    skyscraper.fetch_artwork("snes", sample_artwork)
    -- skyscraper.update_artwork("snes", sample_artwork)
  end
end
