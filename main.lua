require("globals")
love.graphics.setDefaultFilter("nearest", "nearest")

local skyscraper = require("lib.skyscraper")
local splash = require("lib.splash")
local loading = require("lib.loading")
local input = require("helpers.input")

local templates = {}
local current_template = 0

local canvas = love.graphics.newCanvas(640 / 2, 480 / 2)
local default_cover_path = "sample/media/covers/fake-rom.png"
local cover_preview_path = default_cover_path
local cover_preview

local current_platform = "gba"

local w_width, w_height = love.window.getMode()
local spinner = loading.new("spinner", 1)

local state = {
  data = {
    index = 0,
    total = 0,
    title = "N/A",
  },
  error = "",
  loading = nil,
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

function love.load()
  splash.load()
  input.load()
  spinner:load()
  get_templates()
  render_canvas()
  skyscraper.init("config.ini")
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
        cover_preview_path = string.format("data/output/%s/media/covers/%s.png", current_platform, state.data.title)
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
      local roms = nativefs.getDirectoryItems(string.format("roms/%s", current_platform))
      for i = 1, #roms do
        local file = roms[i]
        if file:sub(-4) == ".zip" then
          skyscraper.fetch_and_update_artwork(
            string.format("roms/%s/%s", current_platform, file),
            current_platform,
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

function love.update(dt)
  splash.update(dt)
  input.update(dt)
  spinner:update(dt)
  handle_input()
  update_state()

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
  end
end

function love.draw()
  love.graphics.setBackgroundColor(0, 0, 0, 1)
  splash.draw()

  if splash.finished then
    main_draw()
  end
end
