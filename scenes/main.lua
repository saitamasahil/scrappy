require("globals")
local pprint     = require("lib.pprint")
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
local listitem   = require "lib.gui.listitem"
local popup      = require "lib.gui.popup"
local output_log = require "lib.gui.output_log"

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
-- Debounce configuration for preview generation (seconds)
local preview_debounce = 0.4
local scheduled_preview_at = nil
local scheduled_template_index = nil

-- Ensure sample media folders exist and remove stale fake-rom images
local function prepare_sample_media()
  local base = WORK_DIR .. "/sample/media"
  local sub = { "covers", "screenshots", "wheels" }
  for _, d in ipairs(sub) do
    local dir = string.format("%s/%s", base, d)
    if not nativefs.getInfo(dir) then nativefs.createDirectory(dir) end
    local f = string.format("%s/fake-rom.png", dir)
    if nativefs.getInfo(f) then nativefs.remove(f) end
  end
end

-- TODO: Refactor
local state = {
  error = "",
  loading = nil,
  scraping = false,
  tasks = 0,
  failed_tasks = {},
  total = 0,
  task_in_progress = nil,
  log = {},
  sample_poll = nil,
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

-- Display popup window
local function show_info_window(title, content)
  info_window.visible = true
  info_window.title = title
  info_window.content = content
end

-- Finds first supported output type for a template
local function first_template_output(output_path, platform, game_title)
  local curr_template_path = WORK_DIR .. "/templates/" .. templates[current_template] .. ".xml"
  -- Read supported output types
  local output_types = artwork.get_output_types(curr_template_path)
  local curr_output = "covers"
  -- Find first supported output type
  for key, supported in utils.orderedPairs(output_types) do
    if supported then
      curr_output = artwork.output_map[key]
      break
    end
  end
  return curr_output
end

-- Internal: perform the actual preview generation now
local function generate_preview_now()
  state.loading = true
  local sample_artwork = WORK_DIR .. "/templates/" .. templates[current_template] .. ".xml"
  prepare_sample_media()
  skyscraper.change_artwork(sample_artwork)
  skyscraper.update_sample(sample_artwork)
  local output = first_template_output()
  cover_preview_path = string.format("sample/media/%s/fake-rom.png", output)
  state.sample_poll = { path = cover_preview_path, t0 = love.timer.getTime(), timeout = 3.0 }
end

-- Cycles templates and schedules preview generation after a short pause
local function update_preview(direction)
  -- Cycle templates only
  local direction = direction or 1
  current_template = current_template + direction
  if current_template < 1 then current_template = #templates end
  if current_template > #templates then current_template = 1 end
  -- Debounce: schedule generation after a delay; overwrite any previous schedule
  scheduled_preview_at = love.timer.getTime() + preview_debounce
  scheduled_template_index = current_template
end

-- Updates feedback for template outputs
local function update_output_types()
  local sample_artwork = WORK_DIR .. "/templates/" .. templates[current_template] .. ".xml"
  local keys = { "box", "preview", "splash" }
  local outputs = artwork.get_output_types(sample_artwork)
  for _, key in ipairs(keys) do
    if outputs and outputs[key] then
      local output_item = menu ^ ("output_" .. key)
      output_item.icon = "square_check"
      output_item.focusable = true
    else
      local output_item = menu ^ ("output_" .. key)
      output_item.icon = "square"
      output_item.focusable = false
    end
  end
end

-- Main function to scrape selected platforms
local function scrape_platforms()
  log.write("Scraping artwork")
  -- Load platforms from config
  local platforms = user_config:get().platforms
  if not platforms then
    show_info_window("No platforms to scrape", "Make sure your ROM folders have muOS cores assigned to them.")
    return
  end
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
  for src, dest in utils.orderedPairs(platforms or {}) do
    if not selected_platforms[src] or selected_platforms[src] == "0" or dest == "unmapped" then
      log.write("Skipping " .. src)
      goto skip
    end

    local platform_path = string.format("%s/%s", rom_path, src)

    -- Identify games not in cache
    local uncached_games = false
    local game_list = {}

    -- Get list of files and per-game subfolders
    local files = nativefs.getDirectoryItems(platform_path)
    if not files or #files == 0 then
      log.write("No roms found in " .. platform_path)
      goto skip
    end

    -- Filter files -> ROMs
    local roms = {}
    for _, file in pairs(files) do
      -- Check if it's a file or directory
      local full_path = string.format("%s/%s", platform_path, file)
      local file_info = nativefs.getInfo(full_path)
      if file_info then
        if file_info.type == "file" then
          -- Verify if extension matches peas file
          if skyscraper.filename_matches_extension(file, dest) then
            table.insert(roms, file)
          else
            log.write(string.format("Skipping file %s because it doesn't match any supported extensions for %s", file, dest))
          end
        elseif file_info.type == "directory" then
          -- Ignore hidden metadata folders (e.g., .psmultidisc)
          if file:sub(1,1) == "." then goto continue end
          if dest == "pc" then
            -- DOS often uses per-game folders; treat folder names as ROM identifiers
            table.insert(roms, file)
          else
            -- One-level deep scan: pick the first matching ROM inside the folder (prefer .m3u if present)
            local sub_items = nativefs.getDirectoryItems(full_path) or {}
            local candidate, fallback
            for _, sub in ipairs(sub_items) do
              local rel = string.format("%s/%s", file, sub)
              if skyscraper.filename_matches_extension(sub, dest) or skyscraper.filename_matches_extension(rel, dest) then
                -- Prefer playlist aggregators
                local lower = sub:lower()
                if lower:match("%.m3u$") then candidate = rel; break end
                if not fallback then fallback = rel end
              end
            end
            if candidate or fallback then
              table.insert(roms, candidate or fallback)
            else
              -- No directly matching files in subfolder; keep scanning
            end
          end
          ::continue::
        end
      end
    end

    -- Iterate over ROMs
    for _, rom in pairs(roms) do
      -- Verify if game is cached
      if not uncached_games then
        local res_cache_id = artwork.cached_game_ids[dest] and artwork.cached_game_ids[dest][rom]
        uncached_games = res_cache_id == nil
      end

      -- Get the title without extension
      local game_title = utils.get_filename(rom)

      -- Save in reference map
      if game_file_map[dest] == nil then game_file_map[dest] = {} end
      if game_title then game_file_map[dest][game_title] = rom end
      state.tasks = state.tasks + 1
      table.insert(game_list, game_title)
    end

    if uncached_games then
      skyscraper.fetch_artwork(platform_path, src, dest)
    else
      print("ALL GAMES ARE CACHED FOR " .. src)
      for i = 1, #game_list do
        channels.SKYSCRAPER_GAME_QUEUE:push({
          game = game_list[i],
          platform = dest,
          input_folder = src,
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
      if ui_progress then
        ui_progress.text = string.format("Progress: %d / %d", (state.total - state.tasks), state.total)
      end
      scraping_window.visible = true
    end
  else
    show_info_window("No platforms to scrape", "Please select platforms for scraping in settings.")
  end
  log.write(string.format("Generated %d Skyscraper tasks", state.total))
end

-- Stops all scraping and clears queue
local function halt_scraping()
  channels.SKYSCRAPER_INPUT:clear()
  state.scraping = false
  state.loading = false
  state.failed_tasks = {}
  state.tasks = 0
  state.total = 0
  if scraping_window then scraping_window.visible = false end
end

-- Takes the output from Skyscraper commands and updates state
local function update_state(t)
  if t.error and t.error ~= "" then
    state.error = t.error
    show_info_window("Error", t.error)
    halt_scraping()
  end
  if t.log then
    table.insert(state.log, t.log)
    if #state.log > 6 then
      table.remove(state.log, 1)
    end
    local log_str = ""
    for _, lstr in ipairs(state.log) do
      log_str = log_str .. lstr .. "\n"
    end
    local scraping_log = scraping_window ^ "scraping_log"
    scraping_log.text = log_str
  end
  if t.title then
    state.loading = false
    -- Menu UI elements
    local ui_platform, ui_game = scraping_window ^ "platform", scraping_window ^ "game"
    local ui_progress = scraping_window ^ "progress"
    -- Update UI
    if ui_platform then ui_platform.text = muos.platforms[t.platform] or t.platform or "N/A" end
    if ui_game then ui_game.text = t.title or "N/A" end
    if t.title ~= "fake-rom" then
      log.write(string.format("[%s] Finished Skyscraper task \"%s\"", t.success and "SUCCESS" or "FAILURE", t
        .title))

      -- Remove task from tasks list
      state.tasks = state.tasks - 1
      if t.success then
        -- Reload preview
        -- Read output folder
        local output_path = skyscraper_config:read("main", "gameListFolder")
        output_path = output_path and utils.strip_quotes(output_path) or "data/output"
        -- Get first supported output type
        local curr_output = first_template_output()
        -- Load cover preview art
        cover_preview_path = string.format("%s/%s/media/%s/%s.png", output_path, t.platform, curr_output, t.title)
        state.reload_preview = true
        -- Copy game artwork
        artwork.copy_to_catalogue(t.platform, t.title)
      else
        state.failed_tasks[#state.failed_tasks + 1] = t.title
      end

      -- Update UI
      if ui_progress then
        ui_progress.text = string.format("Game %d of %d", (state.total - state.tasks), state.total)
      end

      -- Check if finished
      if state.scraping and state.tasks == 0 then
        log.write(string.format("Finished scraping %d games. %d failed or skipped", state.total, #state.failed_tasks))
        -- Clear state
        state.scraping = false
        scraping_window.visible = false
        state.log = {}
        -- Clear log
        local scraping_log = scraping_window ^ "scraping_log"
        scraping_log.text = ""
        -- Show success message
        show_info_window(
          "Finished scraping",
          string.format("Scraped %d games, %d failed or skipped! %s", state.total,
            #state.failed_tasks, table.concat(state.failed_tasks, ", "))
        )
        channels.SKYSCRAPER_OUTPUT:clear()
      end
    else
      -- Sample generation finished: reload preview
      local output = first_template_output()
      cover_preview_path = string.format("sample/media/%s/fake-rom.png", output)
      state.reload_preview = true
    end
  end
end

-- Triggered when artwork template changes
local function on_artwork_change(key)
  if key == "left" then
    update_preview(-1)
  elseif key == "right" then
    update_preview(1)
  end
  update_output_types()
end

-- Loads templates in the templates/ dir
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

-- Renders cover art to preview canvas
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

-- Triggered when one of the outputs item is focused
-- output_type: "covers" | "screenshots" | "wheels"
local function on_output_focus(output_type)
  cover_preview_path = string.format("sample/media/%s/fake-rom.png", output_type)
  state.reload_preview = true
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
      -- Background
      love.graphics.setColor(.15, .15, .15);
      love.graphics.rectangle("fill", 0, 0, cw, ch)
      love.graphics.setColor(1, 1, 1);
      -- Artwork (canvas)
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
      -- Background
      love.graphics.setColor(.15, .15, .15);
      love.graphics.rectangle("fill", 0, 0, cw, ch)
      love.graphics.setColor(1, 1, 1);
      -- Artwork (canvas)
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
      + label {
        text = "Select to preview outputs:",
      }
      + listitem {
        id = "output_box",
        text = "Boxart",
        icon = "square",
        onFocus = function()
          on_output_focus("covers")
        end,
      }
      + listitem {
        id = "output_preview",
        text = "Preview",
        icon = "square",
        onFocus = function()
          on_output_focus("screenshots")
        end,
      }
      + listitem {
        id = "output_splash",
        text = "Splash",
        icon = "square",
        onFocus = function()
          on_output_focus("wheels")
        end,
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
          icon = "mag_glass",
          onClick = function() scenes:push("single_scrape") end,
        }
        + button {
          text = "Advanced tools",
          width = w_width * 0.5 - 30,
          icon = "wrench",
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
        + output_log {
          id = "scraping_log",
          width = scraping_window.width,
          height = 100,
        }
      )
  menu:updatePosition(10, 10)

  menu:focusFirstElement()
  if not skyscraper_config:has_credentials() then
    menu = menu + label {
      text = "Open Settings and add your ScreenScraper credentials.",
      icon = "warn",
    }
  end
  if not user_config:has_platforms() then
    menu = menu + label {
      text = "No platforms found; your paths might not have cores assigned",
      icon = "warn",
    }
  end

  update_output_types()
end

-- Reads games from fetch queue and pushes "ready" games into generate queue
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
    local game, platform, input_folder, skipped = ready.game, ready.platform, ready.input_folder, ready.skipped
    print("\nReceived a ready signal, queuing update_artwork for " .. game)
    -- Immediately reflect current platform/game in the UI
    local ui_platform, ui_game = scraping_window ^ "platform", scraping_window ^ "game"
    if ui_platform then ui_platform.text = muos.platforms[platform] or platform or "N/A" end
    if ui_game then ui_game.text = game or "N/A" end
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
    local platform_path = string.format("%s/%s", rom_path, input_folder)
    if not input_folder then
      log.write("No valid platform found")
      return
    end
    if game_file_map[platform] and game_file_map[platform][game] then
      local game_file = game_file_map[platform][game]
      state.task_in_progress = game_file
      print(string.format("Task in progress: %s", game_file))
      skyscraper.update_artwork(platform_path, game_file, input_folder,
        platform, templates[current_template])
    end
  end
end

function main:update(dt)
  local t = channels.SKYSCRAPER_OUTPUT:pop()
  if t then
    update_state(t) -- TODO: Refactor
  end
  -- If a preview was scheduled and the user paused, generate it now
  if scheduled_preview_at and love.timer.getTime() >= scheduled_preview_at then
    -- Ensure we're still on the same template that was scheduled
    if scheduled_template_index == current_template then
      generate_preview_now()
    end
    scheduled_preview_at = nil
    scheduled_template_index = nil
  end
  menu:update(dt)
  if state.reload_preview then
    state.reload_preview = false
    render_to_canvas()
  end

  -- Poll for sample image availability to avoid races with backend output
  if state.sample_poll then
    local p = state.sample_poll
    if nativefs.getInfo(p.path) then
      state.sample_poll = nil
      render_to_canvas()
    elseif (love.timer.getTime() - p.t0) > p.timeout then
      state.sample_poll = nil
      -- give up silently; user can change template again
    end
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
