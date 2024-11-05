local skyscraper = require("lib.skyscraper")
local log        = require("lib.log")
local scenes     = require("lib.scenes")
local loading    = require("lib.loading")
local configs    = require("helpers.config")
local muos       = require("helpers.muos")
local utils      = require("helpers.utils")

local component  = require "lib.gui.badr"
local button     = require "lib.gui.button"
local label      = require "lib.gui.label"
local select     = require "lib.gui.select"
local progress   = require "lib.gui.progress"
local menu, error_window


local background, overlay
local user_config, skyscraper_config = configs.user_config, configs.skyscraper_config
local w_width, w_height = love.window.getMode()
local canvas = love.graphics.newCanvas(w_width, w_height)
local pixel_loading = loading.new("pixel", 0.5)
local default_cover_path = "sample/media/covers/fake-rom.png"
local cover_preview_path = default_cover_path
local cover_preview

local main = {}

local templates = {}
local current_template = 0

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
      error_window.visible = true
      (error_window ^ "error_text").text = state.error
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
      -- Copy game artwork
      copy_game_artwork(state.data.platform, state.data.title)
      -- Update UI
      if menu.children then
        local platform, game, progress, bar = menu ^ "platform", menu ^ "game", menu ^ "progress", menu ^ "progress_bar"
        platform.text = "Platform: " .. state.data.platform
        game.text = "Game: " .. state.data.title
        progress.text = string.format("Progress: %d / %d", (state.total - #state.tasks), state.total)
        bar:setProgress((state.total - #state.tasks) / state.total)
      end
      -- Check if finished
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
      local cover_w, cover_h = cover_preview:getDimensions()
      local canvas_w, canvas_h = canvas:getDimensions()
      love.graphics.draw(cover_preview, canvas_w - cover_w, canvas_h / 2 - cover_h / 2, 0)
    end
  end)
end

function main:load()
  pixel_loading:load()
  get_templates()
  background = load_image("assets/muxsysinfo.png")
  overlay = load_image("assets/preview.png")
  render_to_canvas()

  menu = component:root { column = true, gap = 10 }
  error_window = component { column = true, gap = 10, visible = false }
      + label { text = "Error", icon = "warn" }
      + component {
        id = "error_text",
        text = "",
        width = w_width - 20,
        height = 30,
        _font = love.graphics.getFont(),
        draw = function(self)
          local _, wrappedtext = self._font:getWrap(self.text, self.width - 10)
          love.graphics.push()
          love.graphics.setColor(utils.hex '#2d3436')
          love.graphics.rectangle("fill", self.x, self.y, self.width, #wrappedtext * self.height)
          love.graphics.setColor(1, 1, 1)
          love.graphics.rectangle("line", self.x, self.y, self.width, #wrappedtext * self.height)
          love.graphics.printf(wrappedtext, self.x + 10, self.y + 5, self.width - 10, "left")
          love.graphics.pop()
        end
      }

  local canvasComponent = component {
    overlay = true,
    width = w_width / 2,
    height = w_height / 2,
    draw = function(self)
      local cw, ch = canvas:getDimensions()
      local scale = self.width / cw
      love.graphics.push()
      love.graphics.translate(self.x, self.y)
      love.graphics.scale(scale)
      if self.overlay and background then
        love.graphics.draw(background, 0, 0, 0)
      end
      love.graphics.draw(canvas, 0, 0, 0);
      if self.overlay and overlay then
        love.graphics.draw(overlay, 0, 0, 0)
      end
      love.graphics.setColor(1, 1, 1, 0.5);
      love.graphics.rectangle("line", 0, 0, cw, ch)
      if state.loading or state.scraping then
        love.graphics.setColor(0, 0, 0, 0.5);
        love.graphics.rectangle("fill", 0, 0, cw, ch)
        pixel_loading:draw(cw * scale, ch * scale, 2)
      end
      love.graphics.setColor(1, 1, 1);
      love.graphics.pop()
    end
  }

  local selectionComponent = component { column = true, gap = 10 }
      + select {
        width = w_width / 2 - 30,
        options = templates,
        startIndex = current_template,
        onChange = on_artwork_change
      }
      + button {
        text = "Start scraping",
        width = w_width / 2 - 30,
        onClick = scrape_platforms,
      }

  local infoComponent = component { column = true, gap = 10 }
      + label { id = "platform", text = "Platform: N/A", icon = "controller" }
      + label { id = "game", text = "Game: N/A", icon = "cd" }
      + label { id = "progress", text = "Progress: 0 / 0", icon = "info" }
      + progress { id = "progress_bar", width = w_width / 2 - 30 }

  local top_layout = component { row = true, gap = 10 }
      + (component { column = true, gap = 10 }
        + label { text = "Preview", icon = "file_image" }
        + canvasComponent
      )
      + (component { column = true, gap = 10 }
        + label { text = "Artwork", icon = "file_image" }
        + selectionComponent
        + infoComponent
      )

  local bottom_buttons = component { column = true, gap = 10 }
      + button {
        text = "Settings",
        width = 150,
        onClick = function()
          scenes:switch("settings")
        end,
        focusable = true,
      }
      + button {
        text = "Quit",
        width = 150,
        onClick = function() love.event.quit() end,
        focusable = true,
      }

  menu = menu
      + top_layout
      + bottom_buttons

  menu:updatePosition(10, 10)
  infoComponent:updatePosition(0, w_height / 2 - selectionComponent.height - infoComponent.height - 10)
  bottom_buttons:updatePosition(
    menu.width / 2 - bottom_buttons.width / 2 - 10,
    w_height - top_layout.height - bottom_buttons.height - 30
  )

  error_window:updatePosition(
    w_width / 2 - error_window.width / 2,
    w_height / 2 - error_window.height / 2
  )

  menu:focusFirstElement()
end

function main:update(dt)
  update_state()
  menu:update(dt)
  pixel_loading:update(dt)
  if state.reload_preview and not state.loading then
    state.reload_preview = false
    render_to_canvas()
  end
end

function main:draw()
  menu:draw()
  error_window:draw()
end

function main:keypressed(key)
  if key == "escape" then
    if state.error and state.error ~= "" then
      error_window.visible = false
      state.error = ""
    else
      love.event.quit()
    end
  end
  if not state.scraping then
    menu:keypressed(key)
  end
end

return main
