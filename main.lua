require("globals")
love.graphics.setDefaultFilter("nearest", "nearest")

local skyscraper = require("lib.skyscraper")
local splash = require("lib.splash")
local loading = require("lib.loading")
local input = require("helpers.input")
local config = require("helpers.config")
local muos = require("muos")

local skyscraper_binary = "bin/Skyscraper.aarch64"
local user_config = config.new("user", "config.ini")
local skyscraper_config = config.new("skyscraper", "skyscraper_config.ini")
local templates = {}
local current_template = 0

local canvas = love.graphics.newCanvas(640 / 2, 480 / 2)
local default_cover_path = "sample/media/covers/fake-rom.png"
local cover_preview_path = default_cover_path
local cover_preview

local w_width, w_height = love.window.getMode()
local spinner = loading.new("spinner", 1)

local state = {
  data = {
    title = "N/A",
    platform = "",
  },
  error = "",
  loading = nil,
  scraping = false
}

local function load_image(filename)
  local file_data = nativefs.newFileData(filename)
  if file_data then
    local image_data = love.image.newImageData(file_data)
    if image_data then
      return love.graphics.newImage(image_data)
    end
  end
end

local function update_preview(direction)
  cover_preview_path = default_cover_path
  local direction = direction or 1
  current_template = current_template + direction
  if current_template < 1 then
    current_template = #templates
  end
  if current_template > #templates then
    current_template = 1
  end
  local sample_artwork = WORK_DIR .. "/templates/" .. templates[current_template] .. ".xml"
  skyscraper.change_artwork(sample_artwork)
  skyscraper.update_sample(sample_artwork)
  state.loading = true
  state.reload_preview = true
end

local function get_templates()
  local items = nativefs.getDirectoryItems(WORK_DIR .. "/templates")
  if not items then
    return
  end
  current_template = 1
  for i = 1, #items do
    local file = items[i]
    if file:sub(-4) == ".xml" then
      table.insert(templates, file:sub(1, -5))
    end
  end
end

local function render_canvas()
  print("Rendering canvas")
  cover_preview = load_image(cover_preview_path)
  canvas:renderTo(function()
    love.graphics.clear()
    if cover_preview then
      love.graphics.draw(cover_preview, 0, 0, 0, 0.5, 0.5)
    end
  end)
end

local function setup_configs()
  local rom_path = muos.SD1_PATH
  if user_config:load() then
    skyscraper_binary = user_config:read("main", "binary")
    if user_config:read("main", "sd") == 2 then rom_path = muos.SD2_PATH end
  else
    local loaded = user_config:create_from("config.ini.example")
    if loaded then
      user_config:insert("main", "binary", skyscraper_binary)
      user_config:detect_sd()
      user_config:load_platforms()
      user_config:save()
    end
  end

  if not skyscraper_config:load() then
    local loaded = skyscraper_config:create_from("skyscraper_config.ini.example")
    if loaded then
      print("Config file not present, creating one")
      skyscraper_config:insert("main", "inputFolder", string.format("\"%s\"", rom_path))
      skyscraper_config:insert("main", "cacheFolder", string.format("\"%s/%s\"", WORK_DIR, "data/cache"))
      skyscraper_config:insert("main", "gameListFolder", string.format("\"%s/%s\"", WORK_DIR, "data/output"))
      skyscraper_config:insert("main", "artworkXml", string.format("\"%s/%s\"", WORK_DIR, "templates/box2d.xml"))
      skyscraper_config:save()
    end
  end
end

function love.load()
  splash.load()
  setup_configs()
  input.load()
  spinner:load()
  get_templates()
  render_canvas()
  skyscraper.init("skyscraper_config.ini", skyscraper_binary)
end

local function update_state()
  local t = OUTPUT_CHANNEL:pop()
  if t then
    if t.error ~= "" then
      state.error = t.error
    end
    if t.data ~= nil and next(t.data) ~= nil then
      state.data = t.data
      if state.data.title ~= nil and state.data.title ~= "fake-rom" then
        cover_preview_path = string.format("data/output/%s/media/covers/%s.png", state.data.platform, state.data
          .title)
        state.reload_preview = true
      end
    end
    if t.loading ~= nil then
      state.loading = t.loading
    end
  end
end

local function handle_input()
  input.onEvent(function(event)
    if event == input.events.LEFT then
      -- Load platforms from config
      local platforms = user_config:get().platforms
      state.scraping = true
      -- For each source = destionation pair in config, fetch and update artwork
      for src, dest in pairs(platforms) do
        -- TODO: Respect SD selection in config
        local rom_path = string.format("%s/%s", muos.SD1_PATH, src)
        -- Get list of roms
        local roms = nativefs.getDirectoryItems(rom_path)
        for i = 1, #roms do
          local file = roms[i]
          -- Fetch and update artwork
          skyscraper.fetch_and_update_artwork(
            rom_path,
            string.format(rom_path .. "/" .. file, dest, file),
            dest,
            templates[current_template]
          )
        end
      end
      -- update_preview(-1)
    elseif event == input.events.RIGHT then
      update_preview(1)
    end
  end)
end

local function copy_artwork()
  -- Get list of scraped artwork
  local scraped_art = nativefs.getDirectoryItems("data/output")
  if not scraped_art then
    return
  end
  -- Iterate over folders in output
  for i = 1, #scraped_art do
    local item = scraped_art[i]
    -- Check if item is a folder
    local item_info = nativefs.getInfo(string.format("data/output/%s", item))
    if item_info and item_info.type == "directory" then
      -- Get designated MUOS platform
      local destination_folder = muos.platforms[item]
      if destination_folder then
        -- Destination folder should be in info/catalogue/{System}/box
        destination_folder = string.format("%s/%s/box", muos.CATALOGUE, destination_folder)
        -- Get list of artwork
        local artwork = nativefs.getDirectoryItems(string.format("data/output/%s/media/covers", item))
        for j = 1, #artwork do
          local file = nativefs.read(string.format("data/output/%s/media/covers/%s", item, artwork[j]))
          if file then
            -- Write to destination
            nativefs.write(string.format("%s/%s", destination_folder, artwork[j]), file)
          end
        end
      end
    end
  end
end

function love.update(dt)
  splash.update(dt)
  input.update(dt)
  spinner:update(dt)
  handle_input()
  update_state()

  if state.scraping then
    local input_count = INPUT_CHANNEL:getCount()
    if input_count == 0 then
      state.scraping = false
      copy_artwork()
    end
  end

  if state.reload_preview and not state.loading then
    print("Reloading preview")
    state.reload_preview = false
    render_canvas()
  end
end

local function draw_preview(x, y, width, height)
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.draw(canvas);
  love.graphics.setColor(1, 1, 1, 0.5);
  love.graphics.rectangle("line", 0, 0, width, height)
  if state.loading then
    love.graphics.push()
    love.graphics.setColor(0, 0, 0, 0.5);
    love.graphics.rectangle("fill", 0, 0, width, height)
    spinner:draw(width / 2, height / 2, 0.5)
    love.graphics.pop()
  end
  love.graphics.setColor(1, 1, 1);
  love.graphics.pop()
end

local function main_draw()
  love.graphics.print(templates[current_template], 0, 0)
  love.graphics.rectangle("line", 10, 20, 100, 20)
  draw_preview(0, 0, w_width / 2, w_height / 2)
  if state.error ~= "" then
    love.graphics.print("ERROR: " .. state.error, 10, 40)
  end
  if state.data ~= nil and next(state.data) ~= nil then
    love.graphics.print("Title: " .. state.data.title, 10, 60)
    love.graphics.print("PLATFORM: " .. state.data.platform, 10, 80)
  end
end

function love.draw()
  love.graphics.setBackgroundColor(0, 0, 0, 1)
  splash.draw()

  if splash.finished then
    main_draw()
  end
end
