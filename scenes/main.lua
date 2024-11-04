local skyscraper = require("lib.skyscraper")
local log = require("lib.log")
local scenes = require("lib.scenes")
local loading = require("lib.loading")
local ui = require("lib.ui")
local configs = require("helpers.config")
local muos = require("helpers.muos")
local utils = require("helpers.utils")

local main = {}
local pixel_loading = loading.new("pixel", 0.5)

local user_config, skyscraper_config = configs.user_config, configs.skyscraper_config

local main_ui = ui.new()
local ui_padding = 10
local canvas = love.graphics.newCanvas(640, 480)
local background, overlay
local default_cover_path = "sample/media/covers/fake-rom.png"
local cover_preview_path = default_cover_path
local cover_preview
local templates = {}
local current_template = 0

local w_width, w_height = love.window.getMode()
local state = {
  data = {
    title = "N/A",
    platform = "N/A",
  },
  error = "",
  loading = nil,
  scraping = false,
  tasks = {},
  total = 0,
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
  state.total = 0
end

local function scrape_platforms()
  log.write("Scraping artwork")
  -- Load platforms from config
  local platforms = user_config:get().platforms
  local selected_platforms = user_config:get().selectedPlatforms
  local rom_path, _ = user_config:get_paths()
  -- Set state
  state.scraping = true
  -- For each source = destionation pair in config, fetch and update artwork
  for src, dest in pairs(platforms) do
    if not selected_platforms[src] or selected_platforms[src] == "0" then
      log.write("Skipping " .. src)
      goto skip
    end

    local platform_path = string.format("%s/%s", rom_path, src)
    -- Get list of roms
    local roms = nativefs.getDirectoryItems(platform_path)
    if not roms or #roms == 0 then
      state.error = "No roms found in " .. platform_path
      log.write(state.error)
      return
    end
    for i = 1, #roms do
      local file = roms[i]
      table.insert(state.tasks, file)
      -- Fetch and update artwork
      skyscraper.fetch_and_update_artwork(
        platform_path,
        file,
        dest,
        templates[current_template],
        file
      )
    end
    ::skip::
  end
  state.total = #state.tasks
  log.write(string.format("Generated %d Skyscraper tasks", state.total))
end

local function copy_game_artwork(platform, game)
  log.write(string.format("Copying artwork for %s: %s", platform, game))
  local _, output_path = skyscraper_config:get_paths()
  local _, catalogue_path = user_config:get_paths()
  if output_path == nil or catalogue_path == nil then
    log.write("Missing paths from config")
    return
  end
  local path = string.format("%s/%s/media/covers/%s.png", utils.strip_quotes(output_path), platform, game)
  local destination_folder = muos.platforms[platform]
  if not destination_folder then
    log.write("Catalogue destination folder not found")
    return
  end

  local scraped_art = nativefs.newFileData(path)
  if not scraped_art then
    log.write("Scraped artwork not found")
    return
  end

  destination_folder = string.format("%s/%s/box", catalogue_path, destination_folder)
  local _, err = nativefs.write(string.format("%s/%s.png", destination_folder, game), scraped_art)
  if err then
    log.write(err)
  end
end

local function update_state()
  local t = OUTPUT_CHANNEL:pop()
  if t then
    if t.error and t.error ~= "" then
      state.error = t.error
    end
    if t.data and next(t.data) ~= nil then
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
    if t.task_id then
      log.write("Finished Skyscraper task: " .. t.task_id)
      local pos = 0
      for i = 1, #state.tasks do
        if state.tasks[i] == t.task_id then
          pos = i
          break
        end
      end
      table.remove(state.tasks, pos)
      copy_game_artwork(state.data.platform, state.data.title)
      if state.scraping and #state.tasks == 0 then
        log.write("Finished scraping")
        state.scraping = false
      end
    end
  end
end

local function on_artwork_change(key)
  if key == "left" then
    update_preview(-1)
  elseif key == "right" then
    update_preview(1)
  end
end

local function get_templates()
  local items = nativefs.getDirectoryItems(WORK_DIR .. "/templates")
  if not items then
    return
  end

  current_template = 1
  -- Populate templates
  for i = 1, #items do
    local file = items[i]
    if file:sub(-4) == ".xml" then
      table.insert(templates, file:sub(1, -5))
    end
  end

  -- Get the previously selected template
  local artwork_path = skyscraper_config:read("main", "artworkXml")
  if not artwork_path then
    return
  end

  -- Remove double quotes
  artwork_path = artwork_path:gsub('"', '')
  local artwork_name = artwork_path:match("([^/]+)%.xml$") -- Extract the filename without path and extension
  -- Find the index of artwork_name in templates
  for i = 1, #templates do
    if templates[i] == artwork_name then
      current_template = i
      break
    end
  end
end

local function render_to_canvas()
  -- print("Rendering canvas")
  cover_preview = load_image(cover_preview_path)
  canvas:renderTo(function()
    love.graphics.clear()
    if cover_preview then
      love.graphics.draw(cover_preview, 0, 0, 0)
    end
  end)
end

local function draw_preview(x, y, scale, show_overlay)
  show_overlay = show_overlay or false
  scale = scale or 0.5
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.scale(scale)
  if show_overlay and background then
    love.graphics.draw(background, 0, 0, 0)
  end
  love.graphics.draw(canvas, 0, 0, 0);
  if show_overlay and overlay then
    love.graphics.draw(overlay, 0, 0, 0)
  end
  love.graphics.setColor(1, 1, 1, 0.5);
  love.graphics.rectangle("line", 0, 0, w_width, w_height)
  if state.loading then
    love.graphics.push()
    love.graphics.setColor(0, 0, 0, 0.5);
    love.graphics.rectangle("fill", 0, 0, w_width, w_height)
    pixel_loading:draw(w_width / 2, w_height / 2, 2)
    love.graphics.pop()
  end
  love.graphics.setColor(1, 1, 1);
  love.graphics.pop()
end

local component = require "lib.gui.badr"
local button    = require "lib.gui.button"
local label     = require "lib.gui.label"
local select    = require "lib.gui.select"
local menu      = component:root { column = true, gap = 10 }

function main:load()
  pixel_loading:load()
  get_templates()
  background = load_image("assets/muxsysinfo.png")
  overlay = load_image("assets/preview.png")
  render_to_canvas()

  local customComponent = component { row = true, gap = 10 }
      + label { text = "Preview", icon = "file_image" }

  local bottom_buttons = component { column = true, gap = 10 }
      + button {
        text = "Settings",
        width = 200,
        onClick = function()
          scenes:switch("settings")
        end,
        focusable = true,
      }
      + button {
        text = "Quit",
        width = 200,
        onClick = function() love.event.quit() end,
        focusable = true,
      }

  menu = menu
      + customComponent
      + select {
        width = 200,
        options = templates,
        startIndex = 1,
        onChange = on_artwork_change
      }
      + button {
        text = "Scrape platforms",
        width = 200,
        onClick = scrape_platforms,
      }
      + bottom_buttons

  menu:updatePosition(10, 10)
  bottom_buttons:updatePosition(
    love.graphics.getWidth() * 0.5 - bottom_buttons.width * 0.5,
    love.graphics.getHeight() * 0.5 - bottom_buttons.height * 0.5
  )
end

function main:update(dt)
  update_state()
  menu:update(dt)
  pixel_loading:update(dt)
  if state.reload_preview and not state.loading then
    state.reload_preview = false
    render_to_canvas()
  end

  -- Root layout
  main_ui:layout(0, 0, w_width, w_height, 10, 10, "horizontal")

  -- Left side layout
  main_ui:layout(0, 0, w_width / 2 - 10, w_height, 0, 0)
  main_ui:element({ 0, 0 }, ui.icon_label("Preview", "file_image"))
  main_ui:end_layout()

  -- Right side layout
  main_ui:layout(0, 0, w_width / 2 - 10, w_height, 0, 10)
  main_ui:element({ 0, 26 }, ui.icon_label("Platform: " .. (state.data.platform or "N/A"), "controller"))
  main_ui:element({ 0, 0 }, ui.icon_label("Game: " .. state.data.title, "cd"))
  main_ui:element({ 0, 0 },
    ui.icon_label(string.format("Progress: %d / %d", state.total - #state.tasks, state.total), "info"))
  main_ui:element({ 0, 0, w_width / 2 - ui_padding * 3, 20 }, ui.progress_bar((state.total - #state.tasks) / state.total))
  main_ui:element({ 0, 36 }, ui.icon_label("Artwork", "folder_image"))
  main_ui:element({ 0, 0, w_width / 2 - ui_padding * 3, 30 }, ui.select(templates, current_template, on_artwork_change))
  main_ui:element({ 0, 0, w_width / 2 - ui_padding * 3, 30 }, ui.button("Start scraping", scrape_platforms, "play"))
  main_ui:end_layout()

  main_ui:end_layout() -- End root layout

  -- Advanced section
  main_ui:layout(0, w_height / 2 + 46, w_width, w_height / 2, 10, 10)
  if state.error ~= nil and state.error ~= "" then
    main_ui:element({ 0, 0 }, ui.icon_label("Error", "warn"))
    main_ui:element({ 0, 0, w_width, 30 }, ui.multiline_text(state.error))
  end
  main_ui:end_layout()

  -- Quit button
  main_ui:layout(w_width / 2 - w_width / 8, w_height - 80, w_width, w_height, 0, 5)
  main_ui:element({ 0, 0, w_width / 4, 30 }, ui.button("Settings", function() scenes:push("settings") end))
  main_ui:element({ 0, 0, w_width / 4, 30 }, ui.button("Quit", function() love.event.quit() end))
  main_ui:end_layout()
end

function main:draw()
  -- draw_preview(ui_padding, 36, 0.5, true)
  menu:draw()
end

function main:keypressed(key)
  if key == "escape" then
    love.event.quit()
  end
  if not state.scraping then
    menu:keypressed(key)
  end
end

return main
