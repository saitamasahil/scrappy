_G.love.graphics.setDefaultFilter("nearest", "nearest")

base_scraper_command = "./Skyscraper -s screenscraper"

function load_image(filename)
  local nfs = require("nativefs") -- require from wherever you've put the nativefs.lua
  local file_data = nfs.newFileData(filename)
  if file_data then
    local image_data = love.image.newImageData(file_data)
    if image_data then
      return love.graphics.newImage(image_data)
    end
  end
end

_G.artworks = { "artwork" }
-- _G.artworks = { "retro-dither-logo", "retro-dither", "simple-box-cart" }
_G.current_artwork = 1

function love.load()
  bunny = load_image("sample/media/covers/fake-rom.png")
  path = ""
  local handle = io.popen("pwd")
  if handle ~= nil then
    path = handle:read("*a")
    handle:close()

    path = path:gsub("[\n\r]", "")
  end
end

function love.update(dt)
end

function love.draw()
  love.graphics.draw(bunny, 0, 0, 0, 0.5, 0.5)
  love.graphics.rectangle("line", 0, 0, 640 / 2, 480 / 2)
  love.graphics.print(artworks[current_artwork], 0, 0)
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
    local sample_path = path .. "/sample"
    local artwork_path = path .. "/templates/" .. artworks[current_artwork] .. ".xml"

    print(artworks[current_artwork])

    -- local handle = io.popen("./Skyscraper -v")
    local handle = io.popen("./Skyscraper -p megadrive -d " ..
      sample_path .. " -i " .. sample_path .. " -a " .. artwork_path .. " --flags " .. flags)
    if handle == nil then
      return
    end
    local result = handle:read("*a")
    handle:close()
    -- print(result)

    bunny = load_image("sample/media/covers/fake-rom.png")
  end
end
