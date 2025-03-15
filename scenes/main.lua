require("globals")
local skyscraper = require("lib.skyscraper")
local log        = require("lib.log")
local scenes     = require("lib.scenes")
local loading    = require("lib.loading")
local channels   = require("lib.backend.channels")
local configs    = require("helpers.config")
local utils      = require("helpers.utils")
local artwork    = require("helpers.artwork")
local muos       = require("helpers.muos")

local component  = require "lib.gui.badr"
local button     = require "lib.gui.button"
local label      = require "lib.gui.label"
local select     = require "lib.gui.select"
local popup      = require "lib.gui.popup"
local menu, info_window, scraping_window


local user_config, skyscraper_config = configs.user_config, configs.skyscraper_config
local theme = configs.theme
local loader = loading.new("highlight", 1)

local w_width, w_height = love.window.getMode()
local padding = 10
local canvas = love.graphics.newCanvas(w_width, w_height)
local default_cover_path = "sample/media/covers/fake-rom.png"
local cover_preview_path = default_cover_path
local cover_preview

local main = {}

local templates = {}
local current_template = 1

-- TODO: Refactor
local state = {
  error = "",
  loading = nil,
  scraping = false,
  tasks = 0,
  failed_tasks = {},
  total = 0,
  task_in_progress = nil,
  log = ""
}

--[[
  Format:
  {
    "platform": {
      "game title": "game file"
    }
  }
--]]
local game_file_map = {}

local function show_info_window(title, content)
  info_window.visible = true
  info_window.title = title
  info_window.content = content
end

local function update_preview(direction)
  state.loading = true
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
end

local function scrape_platforms()
  log.write("Scraping artwork")
  -- Load platforms from config, merging mapped and custom
  local platforms = user_config:get().platforms
  -- Load selected platforms
  local selected_platforms = user_config:get().platformsSelected
  local rom_path, _ = user_config:get_paths()
  -- Reset tasks
  state.tasks = 0
  state.failed_tasks = {}
  -- Process cached data from quickid and db
  if user_config:read("main", "parseCache") == "1" then
    artwork.process_cached_data()
  end
  -- For each source = destionation pair in config, fetch and update artwork
  for src, dest in utils.orderedPairs(platforms) do
    if not selected_platforms[src] or selected_platforms[src] == "0" or dest == "unmapped" then
      log.write("Skipping " .. src)
      goto skip
    end

    local platform_path = string.format("%s/%s", rom_path, src)

    -- Identify games not in cache
    local uncached_games = false
    local game_list = {}

    -- Get list of roms
    local roms = nativefs.getDirectoryItems(platform_path)
    if not roms or #roms == 0 then
      log.write("No roms found in " .. platform_path)
      goto skip
    end
    for i = 1, #roms do
      local file = roms[i]
      -- Check if it's a file or directory
      local file_info = nativefs.getInfo(string.format("%s/%s", platform_path, file))
      if file_info and file_info.type == "file" then
        local is_cached = artwork.cached_game_ids[dest] and artwork.cached_game_ids[dest][file]
        uncached_games = not is_cached

        -- Get the title without extension
        local game_title = utils.get_filename(file)

        -- Save in reference map
        if game_file_map[dest] == nil then game_file_map[dest] = {} end
        if game_title then game_file_map[dest][game_title] = file end
        state.tasks = state.tasks + 1
        table.insert(game_list, game_title)
      end
    end

    if uncached_games then
      skyscraper.fetch_artwork(platform_path, dest)
    else
      print("ALL GAMES ARE CACHED FOR " .. dest)
      for i = 1, #game_list do
        channels.SKYSCRAPER_GAME_QUEUE:push({
          game = game_list[i],
          platform = dest,
        })
      end
    end
    ::skip::
  end

  --
  -- TODO: Refactor user feedback
  --
  state.total = state.tasks
  if state.total > 0 then
    state.scraping = true
    if scraping_window then
      local ui_progress = scraping_window ^ "progress"
      ui_progress.text = string.format("Game %d of %d", (state.total - state.tasks), state.total)
      scraping_window.visible = true
    end
  else
    show_info_window("No platforms to scrape", "Please select platforms for scraping in settings.")
  end
  log.write(string.format("Generated %d Skyscraper tasks", state.total))
end

local function halt_scraping()
  channels.SKYSCRAPER_INPUT:clear()
  state.scraping = false
  state.loading = false
  state.failed_tasks = {}
  state.tasks = 0
  state.total = 0
  if scraping_window then scraping_window.visible = false end
end

local function update_state(t)
  if t.error and t.error ~= "" then
    state.error = t.error
    show_info_window("Error", t.error)
    halt_scraping()
  end
  if t.log then
    state.log = state.log .. t.log .. "\n"
    local scraping_log = scraping_window ^ "scraping_log"
    scraping_log.text = state.log
  end
  if t.title then
    state.loading = false
    -- Menu UI elements
    local ui_platform, ui_game = scraping_window ^ "platform", scraping_window ^ "game"
    local ui_progress, ui_bar = scraping_window ^ "progress", scraping_window ^ "progress_bar"
    -- Update UI
    if scraping_window.children then
      ui_platform.text = muos.platforms[t.platform]
      ui_game.text = t.title
    end
    if t.title ~= "fake-rom" then
      log.write(string.format("[%s] Finished Skyscraper task \"%s\"", t.success and "SUCCESS" or "FAILURE", t
        .title))

      -- Remove task from tasks list
      state.tasks = state.tasks - 1
      if t.success then
        -- Reload preview
        cover_preview_path = string.format("data/output/%s/media/covers/%s.png", t.platform, t.title)
        state.reload_preview = true
        -- Copy game artwork
        artwork.copy_to_catalogue(t.platform, t.title)
      else
        state.failed_tasks[#state.failed_tasks + 1] = t.title
      end

      -- Update UI
      if scraping_window.children then
        ui_progress.text = string.format("Game %d of %d", (state.total - state.tasks), state.total)
      end

      -- Check if finished
      if state.scraping and state.tasks == 0 then
        log.write(string.format("Finished scraping %d games. %d failed or skipped", state.total, #state.failed_tasks))
        state.scraping = false
        scraping_window.visible = false
        state.log = ""
        show_info_window(
          "Finished scraping",
          string.format("Scraped %d games, %d failed or skipped! %s", state.total,
            #state.failed_tasks, table.concat(state.failed_tasks, ", "))
        )
      end
    else
      state.reload_preview = true
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
      local template_name = file:sub(1, -5)
      local xml_path = WORK_DIR .. "/templates/" .. file
      if user_config:read("main", "filterTemplates") == "1" then
        local template_resolution = artwork.get_template_resolution(xml_path)
        -- 1. Include if the template resolution is not defined;
        if not template_resolution then
          table.insert(templates, template_name)
        else
          -- 2. Include if the template resolution matches the user resolution;
          if template_resolution == _G.resolution then
            table.insert(templates, template_name)
          else
            -- 3. Include if the template resolution is not matched to a device resolution
            local match_any = false
            for _, resolution in ipairs(_G.device_resolutions) do
              if template_resolution == resolution then
                match_any = true
                break
              end
            end
            if not match_any then
              table.insert(templates, template_name)
            end
          end
        end
      else
        -- Include all templates
        table.insert(templates, template_name)
      end
    end
  end

  -- Get the previously selected template
  local artwork_path = skyscraper_config:read("main", "artworkXml")
  if not artwork_path or artwork_path == "\"\"" then
    artwork_path = string.format("\"%s/%s\"", WORK_DIR, "templates/box2d.xml")
    skyscraper_config:insert("main", "artworkXml", artwork_path)
    skyscraper_config:save()
  end

  artwork_path       = artwork_path:gsub('"', '')          -- Remove double quotes
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
  -- Attempt to load the image
  local img = utils.load_image(cover_preview_path)
  if not img then
    log.write("Failed to load cover preview image")
    return
  end

  cover_preview = img

  canvas:renderTo(function()
    love.graphics.clear(0, 0, 0, 0)
    if cover_preview then
      local cover_w, cover_h = cover_preview:getDimensions()
      local canvas_w, canvas_h = canvas:getDimensions()
      love.graphics.draw(cover_preview, canvas_w - cover_w, canvas_h * 0.5 - cover_h * 0.5, 0)
    end
  end)
end

function main:load()
  loader:load()

  get_templates()
  render_to_canvas()

  menu = component:root { column = true, gap = 10 }
  info_window = popup { visible = false }
  scraping_window = popup { visible = false, title = "Scraping in progress" }

  local canvasComponent = component {
    overlay = true,
    width = w_width * 0.5,
    height = w_height * 0.5,
    draw = function(self)
      local cw, ch = canvas:getDimensions()
      local scale = self.width / cw
      love.graphics.push()
      love.graphics.translate(self.x, self.y)
      love.graphics.scale(scale)
      love.graphics.draw(canvas, 0, 0);
      if state.loading then
        love.graphics.setColor(0, 0, 0, 0.5);
        love.graphics.rectangle("fill", 0, 0, cw, ch)
        loader:draw(cw * scale, ch * scale, 1)
        love.graphics.setColor(1, 1, 1);
      end
      love.graphics.setColor(utils.hex("#EDD113"))
      love.graphics.rectangle("line", 0, 0, cw, ch)
      love.graphics.pop()
    end
  }

  local canvasComponent2 = component {
    overlay = true,
    width = w_width * 0.5 - 2 * padding,
    height = w_height * 0.5 - 2 * padding,
    draw = function(self)
      local cw, ch = canvas:getDimensions()
      local scale = self.width / cw
      love.graphics.push()
      love.graphics.translate(self.x, self.y)
      love.graphics.scale(scale)
      love.graphics.draw(canvas, 0, 0);
      love.graphics.setColor(0, 0, 0, 0.5);
      love.graphics.rectangle("fill", 0, 0, cw, ch)
      loader:draw(cw * scale, ch * scale, 1)
      love.graphics.setColor(utils.hex("#EDD113"))
      love.graphics.rectangle("line", 0, 0, cw, ch)
      love.graphics.pop()
    end
  }

  local selectionComponent = component { column = true, gap = 10 }
      + select {
        width = w_width * 0.5 - 30,
        options = templates,
        startIndex = current_template,
        onChange = on_artwork_change
      }
      + button {
        text = "Start scraping",
        width = w_width * 0.5 - 30,
        onClick = scrape_platforms,
      }

  local infoComponent = component { column = true, gap = 10 }
      + label { id = "platform", text = "Platform: N/A", icon = "controller" }
      + label { id = "game", text = "Game: N/A", icon = "cd" }
      + label { id = "progress", text = "Progress: 0 / 0", icon = "info" }
  -- + progress { id = "progress_bar", width = w_width * 0.5 - 30 }

  local top_layout = component { row = true, gap = 10 }
      + (component { column = true, gap = 10 }
        + label { text = "Preview", icon = "image" }
        + canvasComponent
      )
      + (component { column = true, gap = 10 }
        + label { text = "Artwork", icon = "canvas" }
        + selectionComponent
      -- + infoComponent
      )

  menu = menu
      + top_layout
      + (component { row = true, gap = 10 }
        + button {
          text = "Scrape single ROM",
          width = w_width * 0.5,
          onClick = function() scenes:push("single_scrape") end,
        }
        + button {
          text = "Advanced tools",
          width = w_width * 0.5 - 30,
          onClick = function() scenes:push("tools") end
        }
      )

  scraping_window = scraping_window
      + (   -- Column
        component { column = true, gap = 15 }
        + ( -- Row: Preview + Info
          component { row = true, gap = 10 }
          + canvasComponent2
          + infoComponent
        )
        + component {
          id = "scraping_log",
          width = scraping_window.width - 4 * padding,
          height = 100,
          font = love.graphics.getFont(),
          text = "",
          draw = function(self)
            love.graphics.push()
            love.graphics.setColor(0, 0, 0, 0.5)
            love.graphics.rectangle("fill", self.x, self.y, self.width, self.height)
            love.graphics.setColor(1, 1, 1)
            love.graphics.stencil(function()
              love.graphics.rectangle("fill", self.x, self.y, self.width, self.height)
            end, "replace", 1)
            love.graphics.setStencilTest("greater", 0)

            -- Split the text into lines
            local lines = {}
            for s in self.text:gmatch("[^\r\n]+") do
              table.insert(lines, s)
            end

            -- Calculate the total height of all the lines
            local totalTextHeight = #lines * self.font:getHeight()

            -- Draw text from bottom-up
            local offset = self.height - totalTextHeight
            for i = 1, #lines do
              love.graphics.print(lines[i], self.x + 10, self.y + offset)
              offset = offset + self.font:getHeight()
            end

            love.graphics.setStencilTest()
            love.graphics.pop()
          end
        }
      )
  menu:updatePosition(10, 10)

  menu:focusFirstElement()
  if not skyscraper_config:has_credentials() then
    menu = menu + label {
      text = "No credentials provided in skyscraper_config.ini",
      icon = "warn",
    }
  end
  if not user_config:has_platforms() then
    menu = menu + label {
      text = "No platforms found; your paths might not have cores assigned",
      icon = "warn",
    }
  end
end

local function process_game_queue()
  -- If there's already a task in progress, wait for the finished signal
  if state.task_in_progress then
    -- Wait for the task to finish
    local finished_signal = channels.SKYSCRAPER_GEN_OUTPUT:pop()
    if finished_signal and finished_signal.finished then
      -- Mark task as finished
      print(string.format("Finished task \"%s\"", state.task_in_progress))
      state.task_in_progress = nil
    end
    return -- Don't process anything further until the current task is done
  end

  -- Wait for a ready signal from the Skyscraper backend
  local ready = channels.SKYSCRAPER_GAME_QUEUE:pop()
  if ready then
    local game, platform, skipped = ready.game, ready.platform, ready.skipped
    print("\nReceived a ready signal, queuing update_artwork for " .. game)
    if skipped then
      update_state({
        title = game,
        platform = platform,
        success = false,
      })
      print("Skipping game " .. game)
      return
    end
    local rom_path, _ = user_config:get_paths()
    local platforms = user_config:get().platforms
    local platform_path = ""
    for src, dest in utils.orderedPairs(platforms) do
      if dest == platform then
        platform_path = string.format("%s/%s", rom_path, src)
        break
      end
    end
    if not platform_path then
      log.write("No valid platform found")
      return
    end
    if game_file_map[platform] and game_file_map[platform][game] then
      local game_file = game_file_map[platform][game]
      state.task_in_progress = game_file
      print(string.format("Task in progress: %s", game_file))
      skyscraper.update_artwork(platform_path, game_file,
        platform, templates[current_template])
    end
  end
end

function main:update(dt)
  local t = channels.SKYSCRAPER_OUTPUT:pop()
  if t then
    update_state(t) -- TODO: Refactor
  end
  menu:update(dt)
  if state.reload_preview then
    state.reload_preview = false
    render_to_canvas()
  end

  process_game_queue()
end

function main:draw()
  love.graphics.clear(utils.hex_v(theme:read("main", "BACKGROUND")))
  menu:draw()
  info_window:draw()
  scraping_window:draw()
end

function main:keypressed(key)
  if key == "escape" then
    if info_window.visible then
      info_window.visible = false
    else
      love.event.quit()
    end
  end
  if not state.scraping and not info_window.visible then
    menu:keypressed(key)
  end
  if key == "lalt" then
    scenes:push("settings")
  end
end

return main
