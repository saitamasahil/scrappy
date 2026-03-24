require("globals")
local pprint = require("lib.pprint")
local skyscraper = require("lib.skyscraper")
local log = require("lib.log")
local scenes = require("lib.scenes")
local loading = require("lib.loading")
local channels = require("lib.backend.channels")
local configs = require("helpers.config")
local utils = require("helpers.utils")
local artwork = require("helpers.artwork")
local muos = require("helpers.muos")
local wifi = require("helpers.wifi")
local splash = require("lib.splash")

local component = require "lib.gui.badr"
local button = require "lib.gui.button"
local label = require "lib.gui.label"
local select = require "lib.gui.select"
local listitem = require "lib.gui.listitem"
local popup = require "lib.gui.popup"
local output_log = require "lib.gui.output_log"
local scroll_container = require "lib.gui.scroll_container"

local menu, info_window, scraping_window

local user_config, skyscraper_config = configs.user_config, configs.skyscraper_config
local theme = configs.theme
local loader = loading.new("highlight", 1)

local w_width, w_height = love.window.getMode()
local padding = 10
local canvas = love.graphics.newCanvas(w_width, w_height)
local sample_media_root = "sample/media"
local default_cover_path = sample_media_root .. "/covers/fake-rom.png"
local cover_preview_path = default_cover_path
local output_priority = {"box", "preview", "splash"}
local cover_preview
local wifi_icon
local offline_icon
local wifi_connected = true
local offline_mode = false -- Offline mode setting (disables WiFi checks)
local wifi_check_timer = 0

local main = {}

local templates = {}
local current_template = 1
-- Debounce configuration for preview generation (seconds)
local preview_debounce = 0.6
local scheduled_preview_at = nil
local scheduled_template_index = nil

local scrape_modes = {"Scrape all", "Scrape only missing artwork"}
local current_scrape_mode = 1
local scrape_missing_only = false
local showing_core_reminder = false -- Tracks if the core assignment reminder popup is active
local reminder_fade = 0
local core_reminder_dismissed = false -- Tracking if it was dismissed during this session

-- Dashboard server state
local dashboard_server_running = false
local initial_preview_triggered = false
local dashboard_server_ip = nil
local dashboard_write_timer = 0
local dashboard_state_file = "/tmp/scrappy_dashboard.json"
local dashboard_fetch_progress = "0/0"
local dashboard_log_lines = {}
local dashboard_cached_ip = nil -- Cached before scraping starts (avoids blocking network probe)

-- Load button icons for popup buttons
local button_a_icon = love.graphics.newImage("assets/inputs/switch_button_a.png")
local button_b_icon = love.graphics.newImage("assets/inputs/switch_button_b.png")
local button_x_icon = love.graphics.newImage("assets/inputs/switch_button_x.png")

-- Draw the core assignment reminder popup (matches Clear Cache style)
local function draw_core_reminder_popup()
    if not showing_core_reminder then 
        reminder_fade = 0
        return 
    end

    reminder_fade = reminder_fade + (1 - reminder_fade) * 20 * love.timer.getDelta()
    if reminder_fade > 0.999 then reminder_fade = 1 end

    local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
    local font = love.graphics.getFont()
    local font_h = font:getHeight()

    love.graphics.push()
    love.graphics.origin()

    -- Dim background
    love.graphics.setColor(0, 0, 0, 0.8 * reminder_fade)
    love.graphics.rectangle("fill", 0, 0, sw, sh)

    local popup_scale = 0.85 + 0.15 * reminder_fade
    love.graphics.translate(sw / 2, sh / 2)
    love.graphics.scale(popup_scale, popup_scale)
    love.graphics.translate(-sw / 2, -sh / 2)

    -- Popup box
    local box_w = math.min(sw - 40, 420)
    local box_h = 200
    local box_x = (sw - box_w) / 2
    local box_y = (sh - box_h) / 2

    -- Background
    love.graphics.setColor(0.18, 0.18, 0.18, 1)
    love.graphics.rectangle("fill", box_x, box_y, box_w, box_h, 8, 8)

    -- Border
    love.graphics.setColor(0.4, 0.4, 0.4, 1)
    love.graphics.rectangle("line", box_x, box_y, box_w, box_h, 8, 8)

    love.graphics.setColor(1, 1, 1, 1)

    -- Title
    love.graphics.printf("Reminder", box_x, box_y + 15, box_w, "center")

    -- Message
    local msg = "Make sure you have assigned cores\nto your ROM folders/subfolders\nin muOS before scraping."
    love.graphics.printf(msg, box_x + 15, box_y + 45, box_w - 30, "center")

    -- Button icons
    local icon_size = 24
    local btn_y = box_y + box_h - 45

    -- Calculate total width of both button groups with gap between them
    local gap = 30
    local ok_text = "OK"
    local hide_text = "Don't show again"
    local ok_w = icon_size + 6 + font:getWidth(ok_text)
    local hide_w = icon_size + 6 + font:getWidth(hide_text)
    local total_w = ok_w + gap + hide_w
    local start_x = box_x + (box_w - total_w) / 2

    -- A = OK
    if button_a_icon then
        local iw, ih = button_a_icon:getDimensions()
        local sx, sy = icon_size / iw, icon_size / ih
        love.graphics.draw(button_a_icon, start_x, btn_y, 0, sx, sy)
    end
    love.graphics.print(ok_text, start_x + icon_size + 6, btn_y + (icon_size - font_h) / 2)

    -- B = Don't show again
    local hide_x = start_x + ok_w + gap
    if button_b_icon then
        local iw, ih = button_b_icon:getDimensions()
        local sx, sy = icon_size / iw, icon_size / ih
        love.graphics.draw(button_b_icon, hide_x, btn_y, 0, sx, sy)
    end
    love.graphics.print(hide_text, hide_x + icon_size + 6, btn_y + (icon_size - font_h) / 2)

    love.graphics.pop()
end

-- Ensure sample media folders exist and remove stale fake-rom images
local function prepare_sample_media()
    cover_preview = nil -- Ensure LÖVE releases the file handle
    local base = WORK_DIR .. "/sample/media"
    local sub = {"covers", "screenshots", "wheels", "splashes", "previews"}
    for _, d in ipairs(sub) do
        local dir = string.format("%s/%s", base, d)
        if not nativefs.getInfo(dir) then
            nativefs.createDirectory(dir)
        end
        local f = string.format("%s/fake-rom.png", dir)
        if nativefs.getInfo(f) then
            nativefs.remove(f)
        end
    end
end

-- TODO: Refactor
local state = {
    error = "",
    loading = nil,
    scraping = false,
    fetch_phase = true, -- true = fetching, false = generating
    pending_platforms = 0, -- Number of platforms still fetching
    tasks = 0,
    failed_tasks = {},
    total = 0,
    tasks_in_progress = {}, -- Track multiple concurrent tasks
    max_concurrent_tasks = 3, -- Default, will be read from config
    task_timeout_secs = 120,
    task_meta = nil,
    log = {},
    sample_poll = nil,
    queued_games = {}, -- Games waiting for artwork generation
    selected_output = nil -- Currently displayed artwork type (box/preview/splash)
}

--[[
  Map of games, used to look up game files and their source folders for each platform
  Format:
  {
    "platform": {
      "game title": {
        file = "game file",
        input_folder = "source folder path"
      }
    }
  }
--]]
local game_file_map = {}

-- Display popup window
local function show_info_window(title, content)
    info_window.visible = true
    info_window.fade = 0 -- Explicit reset
    info_window.title = title
    info_window.content = content
end

local function get_required_output_types_for_current_template()
    local curr_template_path = WORK_DIR .. "/templates/" .. templates[current_template] .. ".xml"
    local output_types = artwork.get_output_types(curr_template_path)
    if not output_types then
        return {
            box = true,
            preview = true,
            splash = true
        }
    end
    if not output_types.box and not output_types.preview and not output_types.splash then
        return {
            box = true,
            preview = false,
            splash = false
        }
    end
    return output_types
end

local function resolve_preview_output(preferred_type)
    local outputs = get_required_output_types_for_current_template()
    if preferred_type and outputs[preferred_type] then
        return artwork.output_map[preferred_type], preferred_type
    end
    for _, key in ipairs(output_priority) do
        if outputs[key] then
            return artwork.output_map[key], key
        end
    end
    return artwork.output_map["box"], "box"
end

local function build_media_path(media_root, folder, game_title)
    return string.format("%s/%s/%s.png", media_root, folder, game_title)
end

local function has_missing_catalogue_artwork(dest_platform, game_title)
    if not dest_platform or not game_title or game_title == "" then
        return false
    end
    local _, catalogue_path = user_config:get_paths()
    if not catalogue_path or catalogue_path == "" then
        return true
    end
    local platform_str = muos.platforms[dest_platform] or dest_platform
    local base = string.format("%s/%s", catalogue_path, platform_str)
    local required = get_required_output_types_for_current_template()

    local function missing_for(output_type)
        local fp = string.format("%s/%s/%s.png", base, output_type, game_title)
        if nativefs.getInfo(fp) then
            return false
        end

        -- Check sanitized version (exFAT/sanitized filesystem support)
        local sanitized_title = game_title:gsub(":", "_")
        if sanitized_title ~= game_title then
            local fp_sanitized = string.format("%s/%s/%s.png", base, output_type, sanitized_title)
            if nativefs.getInfo(fp_sanitized) then
                return false
            end
        end

        return true
    end

    if required.box and missing_for("box") then
        return true
    end
    if required.preview and missing_for("preview") then
        return true
    end
    if required.splash and missing_for("splash") then
        return true
    end
    return false
end

-- Internal: perform the actual preview generation now
local function generate_preview_now()
    state.loading = true
    local sample_artwork = WORK_DIR .. "/templates/" .. templates[current_template] .. ".xml"
    prepare_sample_media()
    skyscraper.change_artwork(sample_artwork)
    skyscraper.update_sample(sample_artwork)
    local folder, resolved = resolve_preview_output(state.selected_output)
    state.selected_output = resolved
    cover_preview_path = build_media_path(sample_media_root, folder, "fake-rom")
end

-- Cycles templates and schedules preview generation after a short pause
local function update_preview(direction)
    -- Cycle templates only
    local direction = direction or 1
    current_template = current_template + direction
    if current_template < 1 then
        current_template = #templates
    end
    if current_template > #templates then
        current_template = 1
    end
    -- Debounce: schedule generation after a delay; overwrite any previous schedule
    scheduled_preview_at = love.timer.getTime() + preview_debounce
    scheduled_template_index = current_template
end

local function get_missing_media_types(dest_platform, game_title)
    local result = {
        box = false,
        preview = false,
        splash = false
    }
    if not dest_platform or not game_title or game_title == "" then
        return result
    end
    local _, catalogue_path = user_config:get_paths()
    if not catalogue_path or catalogue_path == "" then
        return get_required_output_types_for_current_template()
    end
    local platform_str = muos.platforms[dest_platform] or dest_platform
    local base = string.format("%s/%s", catalogue_path, platform_str)
    local required = get_required_output_types_for_current_template()

    local function missing_for(output_type)
        local fp = string.format("%s/%s/%s.png", base, output_type, game_title)
        if nativefs.getInfo(fp) then
            return false
        end

        local sanitized_title = game_title:gsub(":", "_")
        if sanitized_title ~= game_title then
            local fp_sanitized = string.format("%s/%s/%s.png", base, output_type, sanitized_title)
            if nativefs.getInfo(fp_sanitized) then
                return false
            end
        end

        return true
    end

    if required.box and missing_for("box") then
        result.box = true
    end
    if required.preview and missing_for("preview") then
        result.preview = true
    end
    if required.splash and missing_for("splash") then
        result.splash = true
    end
    return result
end

-- Updates feedback for template outputs
local function update_output_types()
    local sample_artwork = WORK_DIR .. "/templates/" .. templates[current_template] .. ".xml"
    local keys = {"box", "preview", "splash"}
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
    local _, resolved = resolve_preview_output(state.selected_output)
    state.selected_output = resolved
end

-- Main function to scrape selected platforms
local function scrape_platforms()
    log.write("Scraping artwork")

    -- Check WiFi connection before starting (skip in offline mode)
    if not offline_mode and not wifi.is_connected() then
        log.write("WiFi not connected, aborting scrape")
        show_info_window("No WiFi Connection", "Please connect to WiFi and try again.")
        return
    end

    -- Offline mode only works with "Scrape all" (cached data); missing artwork needs internet
    if offline_mode and scrape_missing_only then
        show_info_window("Offline Mode Active", "Scraping missing artwork requires an internet connection. Use 'Scrape all' in offline mode.")
        return
    end

    -- Load platforms from config
    local platforms = user_config:get().platforms
    if not platforms then
        show_info_window("No platforms to scrape", "Make sure your ROM folders have muOS cores assigned to them.")
        return
    end
    -- Load selected platforms
    local selected_platforms = user_config:get().platformsSelected
    local rom_path, _ = user_config:get_paths()
    state.total = 0
    state.tasks = 0
    state.failed_tasks = {}
    state.queued_games = {}
    state.tasks_in_progress = {}
    state.platform_context = {}
    state.pending_platforms = 0
    game_file_map = {}

    -- Cache IP address now (before network gets busy with ScreenScraper)
    dashboard_cached_ip = utils.get_ip_address()

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

        -- Identify if this platform needs fetching
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
            local full_path = string.format("%s/%s", platform_path, file)
            local file_info = nativefs.getInfo(full_path)
            if file_info then
                if file_info.type == "file" then
                    -- Verify if extension matches peas file
                    if skyscraper.filename_matches_extension(file, dest) then
                        table.insert(roms, file)
                    else
                        log.write(string.format(
                            "Skipping file %s because it doesn't match any supported extensions for %s", file, dest))
                    end
                elseif file_info.type == "directory" then
                    -- Ignore hidden metadata folders (e.g., .psmultidisc)
                    if file:sub(1, 1) == "." then
                        goto next_file
                    end
                    if dest == "pc" then
                        -- DOS often uses per-game folders; treat folder names as ROM identifiers
                        table.insert(roms, file)
                    else
                        -- One-level deep scan: pick the first matching ROM inside the folder (prefer .m3u if present)
                        local sub_items = nativefs.getDirectoryItems(full_path) or {}
                        local candidate, fallback
                        for _, sub in ipairs(sub_items) do
                            local rel = string.format("%s/%s", file, sub)
                            if skyscraper.filename_matches_extension(sub, dest) or
                                skyscraper.filename_matches_extension(rel, dest) then
                                -- Prefer playlist aggregators
                                local lower = sub:lower()
                                if lower:match("%.m3u$") then
                                    candidate = rel;
                                    break
                                end
                                if not fallback then
                                    fallback = rel
                                end
                            end
                        end
                        if candidate or fallback then
                            table.insert(roms, candidate or fallback)
                        end
                    end
                end
            end
            ::next_file::
        end

        -- Iterate over ROMs
        table.sort(roms)
        local seen_titles = {}
        for _, rom in ipairs(roms) do
            -- Get the title without extension
            local game_title = utils.get_filename(rom)

            -- Skip if we already processed a ROM with this same title (e.g. game.zip vs game.min)
            if seen_titles[game_title] then
                goto continue_rom
            end
            seen_titles[game_title] = true

            -- Identify which media types we actually need to scrape for this game
            local missing_in_catalogue = {}
            local needs_scraping = false

            if scrape_missing_only then
                missing_in_catalogue = get_missing_media_types(dest, game_title)
                for _, is_missing in pairs(missing_in_catalogue) do
                    if is_missing then
                        needs_scraping = true
                        break
                    end
                end
            else
                -- Scrape all: we need everything the template requires
                missing_in_catalogue = get_required_output_types_for_current_template()
                needs_scraping = true
            end

            -- Skip game if it has complete artwork and we only care about missing stuff
            if not needs_scraping then
                goto continue_rom
            end

            -- For games that need scraping, verify if required missing pieces are in Skyscraper's cache
            if not uncached_games then
                local pea_key = utils.normalize_platform(dest):lower()
                local cached_res = artwork.cached_game_ids[pea_key] and artwork.cached_game_ids[pea_key][rom:lower()]

                if not cached_res then
                    uncached_games = true
                else
                    -- cached_res is now a table of types { cover = true, screenshot = true, ... }
                    for art_type, is_missing in pairs(missing_in_catalogue) do
                        if is_missing then
                            -- Map Scrappy types to Skyscraper resource types
                            local sky_type = (art_type == "box" and "cover") or (art_type == "preview" and "screenshot") or (art_type == "splash" and "wheel")
                            if not cached_res[sky_type] then
                                -- Missing required media from local cache, MUST fetch from server
                                uncached_games = true
                                break
                            end
                        end
                    end
                end
            end

            -- Save in reference map
            if game_file_map[dest] == nil then
                game_file_map[dest] = {}
            end
            if game_title then
                game_file_map[dest][game_title] = {
                    file = rom,
                    input_folder = src
                }
            end
            state.tasks = state.tasks + 1
            table.insert(game_list, game_title)

            ::continue_rom::
        end

        if uncached_games then
            state.platform_context[dest] = {
                games = game_list, -- Sorted game titles matching execution order
                source = src,
                last_seen_game = nil,
                rom_path = platform_path
            }
            state.pending_platforms = state.pending_platforms + 1
            skyscraper.fetch_artwork(platform_path, src, dest)
        else
            print("ALL GAMES ARE CACHED FOR " .. src)
            -- Queue cached games for generation phase instead of processing immediately
            for i = 1, #game_list do
                table.insert(state.queued_games, {
                    title = game_list[i],
                    platform = dest,
                    input_folder = src,
                    skipped = false
                })
            end
        end
        ::skip::
    end

    state.total = state.tasks
    if state.total > 0 then
        state.scraping = true
        state.fetch_phase = true
        -- NOTE: Do NOT clear queued_games here - it may have been populated above for cached platforms

        -- If no platforms need fetching, go straight to generation
        if state.pending_platforms == 0 then
            log.write("All games cached, starting generation phase")
            state.fetch_phase = false

            -- Push all games directly to the generation queue since we're skipping fetch
            for platform, games in pairs(game_file_map) do
                for game_title, game_info in pairs(games) do
                    -- Use the input_folder stored per-game (fixes bug where multiple folders map to same platform)
                    channels.SKYSCRAPER_GAME_QUEUE:push({
                        game = game_title,
                        platform = platform,
                        input_folder = game_info.input_folder,
                        skipped = false
                    })
                end
            end
        end

        if scraping_window then
            local ui_progress = scraping_window ^ "progress"
            if ui_progress then
                ui_progress.text = string.format("Generating: %d / %d", (state.total - state.tasks), state.total)
            end
            scraping_window.visible = true
            scraping_window.fade = 0 -- Explicit reset
        end
    else
        -- Determine if platforms were actually selected
        local any_platform_selected = false
        for src, dest in pairs(platforms or {}) do
            if selected_platforms[src] and selected_platforms[src] ~= "0" and dest ~= "unmapped" then
                any_platform_selected = true
                break
            end
        end

        if not any_platform_selected then
            show_info_window("No platforms to scrape", "Please select platforms for scraping in settings.")
        elseif scrape_missing_only then
            show_info_window("No missing artwork", "All selected platforms already have complete artwork!")
        else
            show_info_window("No platforms to scrape", "Please select platforms for scraping in settings.")
        end
    end
    log.write(string.format("Generated %d Skyscraper tasks", state.total))
end

-- Dashboard server helpers
local function write_dashboard_state(extra)
    local data = extra or {}
    -- Only set from state if not already provided in 'extra'
    if data.scraping == nil then data.scraping = state.scraping end
    if data.phase == nil then data.phase = state.fetch_phase and "fetch" or "generate" end
    if data.gen_total == nil then data.gen_total = state.total or 0 end
    if data.gen_done == nil then data.gen_done = (state.total or 0) - (state.tasks or 0) end
    if data.failed == nil then data.failed = state.failed_tasks or {} end
    if data.logs == nil then data.logs = dashboard_log_lines end
    if data.fetch_progress == nil then data.fetch_progress = dashboard_fetch_progress end
    if data.pending_platforms == nil then data.pending_platforms = state.pending_platforms or 0 end

    -- Current game/platform from scraping window UI
    if scraping_window then
        local ui_platform = scraping_window ^ "platform"
        local ui_game = scraping_window ^ "game"
        local ui_source = scraping_window ^ "scraper_source"
        if ui_platform then data.platform = ui_platform.text end
        if ui_game then data.game = ui_game.text end
        if ui_source then data.source = ui_source.text end
    end

    -- Build JSON manually (no json lib dependency from main thread)
    local function escape_json_str(s)
        if not s then return "" end
        return s:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t')
    end

    local parts = {}
    parts[#parts + 1] = string.format('"scraping":%s', data.scraping and "true" or "false")
    parts[#parts + 1] = string.format('"phase":"%s"', escape_json_str(data.phase))
    parts[#parts + 1] = string.format('"platform":"%s"', escape_json_str(data.platform or "N/A"))
    parts[#parts + 1] = string.format('"game":"%s"', escape_json_str(data.game or "N/A"))
    parts[#parts + 1] = string.format('"source":"%s"', escape_json_str(data.source or "N/A"))
    parts[#parts + 1] = string.format('"fetch_progress":"%s"', escape_json_str(data.fetch_progress))
    parts[#parts + 1] = string.format('"gen_done":%d', data.gen_done)
    parts[#parts + 1] = string.format('"gen_total":%d', data.gen_total)
    parts[#parts + 1] = string.format('"pending_platforms":%d', data.pending_platforms)

    -- Add theme and accent for live updates
    local theme_name = theme:get_current_name() or "dark"
    local accent_color = configs.user_config:read("main", "customAccent") or "cbaa0f"
    local accent_mode = tostring(configs.user_config:read("main", "accentMode") or "muos"):lower()
    if accent_mode == "muos" then
        accent_color = theme:read("button", "BUTTON_FOCUS") or "cbaa0f"
    end
    parts[#parts + 1] = string.format('"theme":"%s"', escape_json_str(theme_name))
    parts[#parts + 1] = string.format('"accent":"%s"', escape_json_str(accent_color))

    if data.shutdown then
        parts[#parts + 1] = '"shutdown":true'
    end
    if data.finished then
        parts[#parts + 1] = '"finished":true'
    end

    -- Failed tasks array
    local failed_items = {}
    for _, f in ipairs(data.failed) do
        failed_items[#failed_items + 1] = '"' .. escape_json_str(f) .. '"'
    end
    parts[#parts + 1] = '"failed":[' .. table.concat(failed_items, ',') .. ']'

    -- Logs array
    local log_items = {}
    for _, l in ipairs(data.logs) do
        log_items[#log_items + 1] = '"' .. escape_json_str(l) .. '"'
    end
    parts[#parts + 1] = '"logs":[' .. table.concat(log_items, ',') .. ']'

    local json_str = '{' .. table.concat(parts, ',') .. '}'

    local f = io.open(dashboard_state_file, "w")
    if f then
        f:write(json_str)
        f:close()
    end
end

local function toggle_dashboard_server()
    if dashboard_server_running then
        -- Signal the server to shutdown gracefully via state file first
        write_dashboard_state({shutdown = true})
        
        -- Then force kill in a background thread to be sure
        local stop_thread = love.thread.newThread([[
            local count = 0
            while count < 4 do
                os.execute("pkill -9 -f scrape_dashboard.py")
                os.execute("sleep 0.5")
                count = count + 1
            end
        ]])
        stop_thread:start()
        
        dashboard_server_running = false
        dashboard_server_ip = nil
        os.remove(dashboard_state_file)
        dashboard_log_lines = {}
        dashboard_fetch_progress = "0/0"
        log.write("Dashboard server stopped")
        return
    end

    local ip = dashboard_cached_ip or utils.get_ip_address()
    if ip then
        -- Ensure any zombie servers are gone before starting
        os.execute("pkill -9 -f scrape_dashboard.py")
        
        -- Write initial state before launching
        write_dashboard_state()

        -- Build command
        local server_path = WORK_DIR .. "/scripts/scrape_dashboard.py"
        local logo_path = WORK_DIR .. "/assets/scrappy_logo.png"
        local theme_name = theme:get_current_name() or "dark"
        local accent_color = configs.user_config:read("main", "customAccent") or "cbaa0f"
        local accent_mode = tostring(configs.user_config:read("main", "accentMode") or "muos"):lower()
        if accent_mode == "muos" then
            accent_color = theme:read("button", "BUTTON_FOCUS") or "cbaa0f"
        end
        
        local cmd = string.format('python3 "%s" --theme %s --accent "%s" --logo "%s" > /dev/null 2>&1',
            server_path, theme_name, accent_color, logo_path)

        -- Launch in a LÖVE background thread
        local launch_thread = love.thread.newThread([[
            local cmd = love.thread.getChannel("dashboard_launch"):pop()
            if cmd then
                os.execute(cmd)
            end
        ]])
        love.thread.getChannel("dashboard_launch"):push(cmd)
        launch_thread:start()

        dashboard_server_running = true
        dashboard_server_ip = ip
        log.write(string.format('Go to http://%s:8081 on phone/PC (same WiFi)', ip))
    else
        log.write("No IP found! Connect to WiFi.")
    end
end

-- Stops all scraping and clears queue
local function halt_scraping()
    -- Clear UI output channel (restart_threads handles backend channels)
    channels.TASK_OUTPUT:clear()

    log.write("Halting scraping...")

    -- Restart threads to ensure clean state (handles killing processes and clearing channels)
    skyscraper.restart_threads()

    state.scraping = false
    state.loading = false
    state.fetch_phase = true
    state.pending_platforms = 0
    state.queued_games = {}
    state.failed_tasks = {}
    state.tasks = 0
    state.total = 0
    state.tasks_in_progress = {} -- Clear concurrent tasks
    state.platform_context = {} -- Clear platform context
    if scraping_window then
        scraping_window.visible = false
    end

    -- Write final state to dashboard (keep server running so user can review)
    if dashboard_server_running then
        write_dashboard_state()
    end
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

        -- Track log lines for dashboard (keep last 20)
        table.insert(dashboard_log_lines, t.log)
        if #dashboard_log_lines > 20 then
            table.remove(dashboard_log_lines, 1)
        end
        local log_str = ""
        for _, lstr in ipairs(state.log) do
            log_str = log_str .. lstr .. "\n"
        end
        local scraping_log = scraping_window ^ "scraping_log"
        if scraping_log then
            scraping_log.text = log_str
        end

        -- Detailed signal for preview generation
        if t.log:match("%[gen%] Finished \"fake%-rom\"") then
            state.reload_preview = true
        end

        -- Parse fetch progress from Skyscraper output (e.g., "#26/761 (T2) Pass 1")
        if t.log then
            local current, total = t.log:match("#(%d+)/(%d+)")
            if current and total then
                local ui_fetch_progress = scraping_window ^ "fetch_progress"
                if ui_fetch_progress then
                    ui_fetch_progress.text = string.format("Fetching: %s / %s", current, total)
                end
                dashboard_fetch_progress = current .. "/" .. total
            end
        end

        -- Track the last processed game for the current platform
        -- Log patterns: "Game 'Title' found!", "Game 'Title' not found", etc.
        local game_title_pats = {
            "Game '(.-)' found!", "Game '(.-)' not found", "Game '(.-)' match too low", "Skipping game '(.-)' since"
        }
        for _, pat in ipairs(game_title_pats) do
            local game = t.log:match(pat)
            if game then
                local platform_context_map = state.platform_context or {}
                for plat, context in pairs(platform_context_map) do
                    -- Check if game is in this platform's game list
                    if game_file_map[plat] and game_file_map[plat][game] then
                         context.last_seen_game = game
                         break
                    end
                end
                break
            end
        end

        -- Check if this is a fetch completion message
        local completed_platform = t.log:match("%[fetch%] Platform (.-) completed")
        if completed_platform then
            
            -- RESUME LOGIC (only if still scraping and not manually halted)
            local context = state.platform_context and state.platform_context[completed_platform]
            local resumed = false
            
            if state.scraping and context then
                -- log.write(string.format("Checking resume for %s. Last seen: %s", completed_platform, context.last_seen_game or "nil"))
                local last_game_in_list = context.games[#context.games]
                
                -- If we haven't seen the last game, we probably crashed/exited early
                if context.last_seen_game ~= last_game_in_list then
                    print(string.format("Early exit detected for %s! Expected last: %s", completed_platform, last_game_in_list))
                    log.write(string.format("Early exit detected for %s. Resuming...", completed_platform))
                    
                    -- Find where to resume
                    local resume_index = 1
                    if context.last_seen_game then
                        for i, g in ipairs(context.games) do
                            if g == context.last_seen_game then
                                resume_index = i + 1
                                break
                            end
                        end
                    end
                    
                    if resume_index <= #context.games then
                        local next_game = context.games[resume_index]
                        
                        -- Find the rom file for this game title
                        local game_info = game_file_map[completed_platform][next_game]
                        local next_rom_file = game_info and game_info.file
                        
                        if next_rom_file then
                             resumed = true
                             -- Call fetch_artwork again with start_at
                             skyscraper.fetch_artwork(context.rom_path, context.source, completed_platform, next_rom_file)
                        else
                             log.write("Could not find file for resume game: " .. next_game)
                        end
                    end
                end
            end

            if not resumed then
                state.pending_platforms = math.max(0, state.pending_platforms - 1)
                print(string.format("Platform fetch completed. Pending: %d", state.pending_platforms))

                -- When all fetches complete, transition to generation phase
                if state.pending_platforms == 0 and state.fetch_phase then
                    state.fetch_phase = false
                    print(string.format("==== FETCH PHASE COMPLETE ===="))
    
                    
                    -- SYNC TASK COUNT:
                    -- Skyscraper fetch might ignore some files (e.g. unrecognized extension, read error)
                    -- so we must update our task count to match what was ACTUALLY queued for generation.
                    -- Otherwise, we might wait forever for tasks that will never start.
                    local old_total = state.total
                    state.total = #state.queued_games
                    state.tasks = #state.queued_games
                    
                    print(string.format("Transitioning to GENERATION PHASE with %d queued games (was expecting %d)", state.total, old_total))
                    log.write(string.format("Syncing task count: %d -> %d to match queued games", old_total, state.total))
    
                    -- Update UI to reflect new total
                    local ui_progress = scraping_window ^ "progress"
                    if ui_progress then
                        ui_progress.text = string.format("Generating: %d / %d", (state.total - state.tasks), state.total)
                    end
    
                    -- Start processing queued games by pushing them back to the queue
                    for i, game_info in ipairs(state.queued_games) do
                        local game_title = game_info.title or game_info.game -- Support both keys for backward compatibility
                        print(string.format("[%d/%d] Queueing %s for generation", i, #state.queued_games, game_title))
                        channels.SKYSCRAPER_GAME_QUEUE:push({
                            game = game_title,
                            platform = game_info.platform,
                            input_folder = game_info.input_folder,
                            skipped = false
                        })
                    end
                    -- Clear queued_games after processing to prevent reprocessing
                    state.queued_games = {}
                end
            end
        end
    end
    if t.title then
        state.loading = false
        -- Menu UI elements
        local ui_platform, ui_game = scraping_window ^ "platform", scraping_window ^ "game"
        local ui_progress = scraping_window ^ "progress"
        local ui_fetch_progress = scraping_window ^ "fetch_progress"
        -- Update UI
        if ui_platform then
            ui_platform.text = muos.platforms[t.platform] or t.platform or "N/A"
        end
        if ui_game then
            ui_game.text = t.title or "N/A"
        end

        local ui_source = scraping_window ^ "scraper_source"
        if ui_source then
            if state.fetch_phase then
                local module = skyscraper.get_module_name(t.platform)
                local module_map = {
                    screenscraper = "ScreenScraper",
                    thegamesdb = "TheGamesDB",
                    import = "Import"
                }
                ui_source.text = string.format("Source: %s", module_map[module] or module or "N/A")
            else
                ui_source.text = "Source: Local"
            end
        end
        if t.title ~= "fake-rom" then
            log.write(string.format("[%s] Finished Skyscraper task \"%s\"", t.success and "SUCCESS" or "FAILURE",
                t.title))

            -- Remove task from tasks list
            state.tasks = state.tasks - 1
            if t.success then
                -- Reload preview using the user's selected output type
                local output_path = skyscraper_config:read("main", "gameListFolder")
                output_path = output_path and utils.strip_quotes(output_path) or "data/output"
                local normalized_platform = utils.normalize_platform(t.platform)
                local media_root = string.format("%s/%s/media", output_path, normalized_platform)
                local folder, resolved = resolve_preview_output(state.selected_output)
                state.selected_output = resolved
                cover_preview_path = build_media_path(media_root, folder, t.title)
                state.reload_preview = true
                -- Copy game artwork
                artwork.copy_to_catalogue(t.platform, t.title)
            else
                state.failed_tasks[#state.failed_tasks + 1] = t.title
            end

            -- Update UI
            if ui_progress then
                ui_progress.text = string.format("Generating: %d / %d", (state.total - state.tasks), state.total)
            end

            -- Check if finished
            if state.scraping and state.tasks == 0 then
                local grand_total = state.total
                log.write(string.format("Finished scraping %d games. %d failed or skipped", grand_total,
                    #state.failed_tasks))

                -- Clear state
                state.scraping = false

                -- Notify dashboard of completion (keep server running so user can see results)
                if dashboard_server_running then
                    write_dashboard_state({ finished = true })
                end

                scraping_window.visible = false
                state.log = {}
                -- Clear log
                local scraping_log = scraping_window ^ "scraping_log"
                scraping_log.text = ""
                -- Show success message
                show_info_window("Finished scraping",
                    string.format("Scraped %d games, %d failed or skipped! %s", grand_total, #state.failed_tasks,
                        table.concat(state.failed_tasks, ", ")))
                channels.SKYSCRAPER_OUTPUT:clear()
            end
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

local function on_scrape_mode_change(_, idx)
    current_scrape_mode = idx
    scrape_missing_only = current_scrape_mode == 2
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

    artwork_path = artwork_path:gsub('"', '') -- Remove double quotes
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

-- Triggered when one of the outputs item is focused ("box" | "preview" | "splash")
local function on_output_focus(output_type)
    local folder, resolved = resolve_preview_output(output_type)
    state.selected_output = resolved
    cover_preview_path = build_media_path(sample_media_root, folder, "fake-rom")
    state.reload_preview = true
end

function main:load()
    loader:load()
    if not wifi_icon then
        if nativefs.getInfo("assets/icons/wifi.png") then
            wifi_icon = love.graphics.newImage("assets/icons/wifi.png")
        end
    end
    if not offline_icon then
        if nativefs.getInfo("assets/icons/offline.png") then
            offline_icon = love.graphics.newImage("assets/icons/offline.png")
        end
    end
    -- Load offline mode setting from config
    local saved_offline = user_config:read("main", "offlineMode")
    offline_mode = (saved_offline == "1")

    wifi_connected = wifi.is_connected()
    wifi_check_timer = 0

    get_templates()
    local initial_folder, resolved = resolve_preview_output()
    state.selected_output = resolved
    cover_preview_path = build_media_path(sample_media_root, initial_folder, "fake-rom")
    render_to_canvas()

    -- Load concurrent generation setting from config (1-8, default 3)
    local concurrent_cfg = user_config:read("main", "concurrentGeneration")
    local concurrent = tonumber(concurrent_cfg or "") or 3
    if concurrent < 1 then
        concurrent = 1
    end
    if concurrent > 8 then
        concurrent = 8
    end
    state.max_concurrent_tasks = concurrent
    log.write(string.format("Concurrent artwork generation tasks: %d", state.max_concurrent_tasks))

    menu = component:root{
        column = true,
        gap = 10
    }
    info_window = popup {
        visible = false
    }
    scraping_window = popup {
        visible = false,
        title = "Scraping in progress"
    }

    -- Show core assignment reminder on first load (unless user dismissed it)
    if user_config:read("main", "hideCoreReminder") ~= "1" then
        showing_core_reminder = true
    end

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
            -- Background (uses theme color)
            local preview_bg = theme:read_color("button", "BUTTON_BACKGROUND", "#2d3436")
            love.graphics.setColor(preview_bg)
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
            love.graphics.setColor(theme:read_color("button", "BUTTON_FOCUS", "#cbaa0f"))
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", 0, 0, cw, ch)
            love.graphics.setLineWidth(1)
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
            -- Background (uses theme color)
            local preview_bg = theme:read_color("button", "BUTTON_BACKGROUND", "#2d3436")
            love.graphics.setColor(preview_bg)
            love.graphics.rectangle("fill", 0, 0, cw, ch)
            love.graphics.setColor(1, 1, 1);
            -- Artwork (canvas)
            love.graphics.draw(canvas, 0, 0);
            love.graphics.setColor(0, 0, 0, 0.5);
            love.graphics.rectangle("fill", 0, 0, cw, ch)
            loader:draw(cw * scale, ch * scale, 1)
            love.graphics.setColor(theme:read_color("button", "BUTTON_FOCUS", "#cbaa0f"))
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", 0, 0, cw, ch)
            love.graphics.setLineWidth(1)
            love.graphics.pop()
        end
    }

    local selectionComponent = component {
        column = true,
        gap = 10
    } + select {
        width = w_width * 0.5 - 30,
        options = templates,
        startIndex = current_template,
        onChange = on_artwork_change,
        onFocus = function() on_output_focus("box") end
    } + select {
        width = w_width * 0.5 - 30,
        options = scrape_modes,
        startIndex = current_scrape_mode,
        onChange = on_scrape_mode_change,
        onFocus = function() on_output_focus("box") end
    } + button {
        text = "Start scraping",
        width = w_width * 0.5 - 30,
        onClick = scrape_platforms,
        onFocus = function() on_output_focus("box") end
    } + label {
        text = "Select to preview outputs:"
    } + listitem {
        id = "output_box",
        text = "Boxart",
        icon = "square",
        onFocus = function()
            on_output_focus("box")
        end
    } + listitem {
        id = "output_preview",
        text = "Preview",
        icon = "square",
        onFocus = function()
            on_output_focus("preview")
        end
    } + listitem {
        id = "output_splash",
        text = "Splash",
        icon = "square",
        onFocus = function()
            on_output_focus("splash")
        end
    }

    local popup_max_width = love.graphics.getWidth() * 0.85
    local canvas_width = w_width * 0.5 - 20
    local info_width = popup_max_width - canvas_width - 10 -- account for 10px row gap

    local infoComponent = component {
        column = true,
        gap = 10,
        width = info_width
    } + label {
        id = "platform",
        text = "Platform: N/A",
        icon = "controller",
        max_width = info_width
    } + label {
        id = "game",
        text = "Game: N/A",
        icon = "cd",
        max_width = info_width
    } + label {
        id = "fetch_progress",
        text = "Fetching: 0 / 0",
        icon = "downloading",
        max_width = info_width
    } + label {
        id = "progress",
        text = "Generating: 0 / 0",
        icon = "generating",
        max_width = info_width
    } + label {
        id = "scraper_source",
        text = "Source: N/A",
        icon = "source",
        max_width = info_width
    }
    -- + progress { id = "progress_bar", width = w_width * 0.5 - 30 }

    local top_layout = component {
        row = true,
        gap = 10
    } + (component {
        column = true,
        gap = 10
    } + label {
        text = "Preview",
        icon = "image"
    } + canvasComponent) + (component {
        column = true,
        gap = 10
    } + label {
        text = "Artwork",
        icon = "canvas"
    } + selectionComponent -- + infoComponent
    )

    menu = menu + top_layout + (component {
        row = true,
        gap = 10
    } + button {
        text = "Scrape single ROM",
        width = w_width * 0.5,
        icon = "mag_glass",
        onClick = function()
            scenes:push("single_scrape")
        end,
        onFocus = function() on_output_focus("box") end
    } + button {
        text = "Advanced tools",
        width = w_width * 0.5 - 30,
        icon = "wrench",
        onClick = function()
            scenes:push("tools")
        end,
        onFocus = function() on_output_focus("box") end
    })

    scraping_window = scraping_window + ( -- Column
    component {
        column = true,
        gap = 15,
        width = w_width * 0.85
    } + ( -- Row: Preview + Info
    component {
        row = true,
        gap = 10
    } + canvasComponent2 + infoComponent) + output_log {
        id = "scraping_log",
        width = w_width * 0.85,
        height = 100
    } + component {
        id = "dashboard_hint",
        width = w_width * 0.85,
        height = 20,
        draw = function(self)
            if not self.visible then return end
            love.graphics.push()
            local icon_size = 20
            local gap = 6
            -- Draw X button icon
            if button_x_icon then
                local iw, ih = button_x_icon:getDimensions()
                local sx, sy = icon_size / iw, icon_size / ih
                local c = configs.theme:read_color("label", "LABEL_TEXT", "#dfe6e9")
                love.graphics.setColor(c)
                love.graphics.draw(button_x_icon, self.x, self.y, 0, sx, sy)
            end
            -- Draw text
            local txt
            if dashboard_server_running and dashboard_server_ip then
                txt = "Go to http://" .. dashboard_server_ip .. ":8081 on phone/PC (same WiFi)"
            else
                txt = "Launch Live Dashboard"
            end
            love.graphics.print(txt, self.x + icon_size + gap, self.y + (icon_size - love.graphics.getFont():getHeight()) / 2)
            love.graphics.setColor(1, 1, 1)
            love.graphics.pop()
        end
    })
    menu:updatePosition(10, 10)

    menu:focusFirstElement()
    local current_scraper = user_config:read("main", "scraperModule") or "screenscraper"
    if not skyscraper_config:has_credentials(current_scraper) then
        local warn_text = current_scraper == "thegamesdb" 
            and "TheGamesDB scraping is limited without an API key. Add it in Settings."
            or "Open Settings and add your ScreenScraper credentials."
        menu = menu + label {
            id = "ss_warning",
            text = warn_text,
            icon = "warn",
            max_width = w_width * 0.95
        }
    end
    if not user_config:has_platforms() then
        menu = menu + label {
            text = "No platforms found; your paths might not have cores assigned",
            icon = "warn"
        }
    end

    update_output_types()
    -- Flag for initial preview generation after splash
    initial_preview_triggered = false
end

-- Reads games from fetch queue and pushes "ready" games into generate queue
local function process_game_queue()
    -- Drain ALL finished signals (not just one per frame)
    -- This fixes the issue where scraping gets stuck near the end with concurrent tasks
    while true do
        local finished_signal = channels.SKYSCRAPER_GEN_OUTPUT:pop()
        if not finished_signal then
            break
        end

        if finished_signal.finished then
            -- Find and remove the finished task by matching game_file and platform
            local found = false
            for i, task in ipairs(state.tasks_in_progress) do
                if task.game_file == finished_signal.game and task.platform == finished_signal.platform then
                    print(string.format("Finished task \"%s\" on platform %s", task.game_file, task.platform))
                    table.remove(state.tasks_in_progress, i)
                    found = true
                    break
                end
            end

            -- Fallback: if no exact match found but we have tasks for this platform, remove the oldest one
            -- This prevents stuck states when game file names don't match exactly
            if not found and #state.tasks_in_progress > 0 then
                for i, task in ipairs(state.tasks_in_progress) do
                    if task.platform == finished_signal.platform then
                        print(string.format("Fallback: removing task \"%s\" on platform %s (signal game: %s)",
                            task.game_file, task.platform, finished_signal.game or "nil"))
                        table.remove(state.tasks_in_progress, i)
                        found = true
                        break
                    end
                end
            end

            -- Last resort: just remove the oldest task to prevent permanent stuck state
            if not found and #state.tasks_in_progress > 0 then
                print(string.format("Last resort: removing oldest task \"%s\"",
                    state.tasks_in_progress[1].game_file or "unknown"))
                table.remove(state.tasks_in_progress, 1)
            end
        end
    end

    -- If we're at max capacity, wait before processing more
    if #state.tasks_in_progress >= state.max_concurrent_tasks then
        return
    end

    -- Drain ALL game events from Skyscraper (not just one per frame)
    -- This prevents race conditions where "fetch completed" arrives before all "game found" events are processed
    while true do
        -- Check if we're at max concurrent capacity (only relevant for Generation Phase)
        if not state.fetch_phase and #state.tasks_in_progress >= state.max_concurrent_tasks then
            break
        end

        local ready = channels.SKYSCRAPER_GAME_QUEUE:pop()
        if not ready then break end

        local game, platform, input_folder, skipped = ready.game, ready.platform, ready.input_folder, ready.skipped
        print("\nReceived a ready signal, queuing update_artwork for " .. game)
        -- Immediately reflect current platform/game in the UI
        local ui_platform, ui_game = scraping_window ^ "platform", scraping_window ^ "game"
        if ui_platform then
            ui_platform.text = muos.platforms[platform] or platform or "N/A"
        end
        if ui_game then
            ui_game.text = game or "N/A"
        end

        local ui_source = scraping_window ^ "scraper_source"
        if ui_source then
            if state.fetch_phase then
                local module = skyscraper.get_module_name(platform)
                local module_map = {
                    screenscraper = "ScreenScraper",
                    thegamesdb = "TheGamesDB",
                    import = "Import"
                }
                ui_source.text = string.format("Source: %s", module_map[module] or module or "N/A")
            else
                ui_source.text = "Source: Local"
            end
        end
        if skipped then
            if state.fetch_phase then
                state.failed_tasks[#state.failed_tasks + 1] = game
            else
                update_state({
                    title = game,
                    platform = platform,
                    success = false
                })
            end
            print("Skipping game " .. game)
            -- continue to next item in loop
        else
            local rom_path, _ = user_config:get_paths()
            local platform_path = string.format("%s/%s", rom_path, input_folder)
            if not input_folder then
                log.write("No valid platform found")
                -- Send finished signal to prevent blocking
                channels.SKYSCRAPER_GEN_OUTPUT:push({
                    finished = true
                })
                -- continue
            elseif game_file_map[platform] and game_file_map[platform][game] then
                local game_info = game_file_map[platform][game]
                local game_file = game_info.file
                -- Use the stored input_folder if available (fixes multi-folder platform bug)
                if not input_folder then
                    input_folder = game_info.input_folder
                end

                -- Two-phase logic: queue during fetch, process during generation
                if state.fetch_phase then
                    -- FETCH PHASE: queue the game for later processing
                    print(string.format("Fetched: %s/%s - queuing for generation phase", platform, game))
                    table.insert(state.queued_games, {
                        platform = platform,
                        game_file = game_file,
                        platform_path = platform_path,
                        input_folder = input_folder,
                        title = game
                    })
                else
                    -- GENERATION PHASE: process immediately
                    print(string.format("Processing queued game: %s/%s", platform, game))
                    table.insert(state.tasks_in_progress, {
                        game_file = game_file,
                        started_at = love.timer.getTime(),
                        title = game,
                        platform = platform,
                        input_folder = input_folder
                    })
                    print(string.format("Task in progress: %s (Total concurrent: %d)", game_file,
                        #state.tasks_in_progress))
                    skyscraper.update_artwork(platform_path, game_file, input_folder, platform,
                        templates[current_template])
                end
            else
                log.write(string.format("Game file not found in map for %s on platform %s", game, platform))
                -- Send finished signal to prevent blocking
                channels.SKYSCRAPER_GEN_OUTPUT:push({
                    finished = true
                })
                -- Do NOT call update_state here - this game was never added to state.tasks
                -- (filtered out by scrape_missing_only or other conditions)
                print(string.format("Skipping game %s (not in game_file_map, likely filtered)", game))
            end
        end
    end
end

function main:update(dt)
    -- Periodically check wifi status (every 5 seconds)
    wifi_check_timer = wifi_check_timer + dt
    if wifi_check_timer > 5 then
        wifi_check_timer = 0
        wifi_connected = wifi.is_connected()
    end

    -- Process game queue FIRST to ensure all "found" games are registered 
    -- before we process any "completed" signals in the output loop below.
    process_game_queue()

    -- Drain output messages from Skyscraper (limited to 50 per frame)
    -- This prevents message pile-up while avoiding UI freeze if volume is high
    local processed_count = 0
    while processed_count < 50 do
        local t = channels.SKYSCRAPER_OUTPUT:pop()
        if not t then
            break
        end
        update_state(t)
        processed_count = processed_count + 1
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

    -- Watchdog: if a generate task hangs beyond timeout, mark it failed and unblock
    -- if state.task_in_progress and state.task_started_at then
    --   local elapsed = love.timer.getTime() - state.task_started_at
    --   if elapsed > (state.task_timeout_secs or 120) then
    --     local meta = state.task_meta or { title = utils.get_filename(state.task_in_progress), platform = "unknown" }
    --     log.write(string.format("Watchdog timeout after %ds for '%s' (%s)", math.floor(elapsed), meta.title or "N/A", meta.platform or "N/A"))
    --     -- Inform UI about failure
    --     channels.SKYSCRAPER_OUTPUT:push({
    --       title = meta.title,
    --       platform = meta.platform,
    --       success = false,
    --       error = "Operation timed out",
    --     })
    --     -- Unblock processing queue
    --     channels.SKYSCRAPER_GEN_OUTPUT:push({ finished = true })
    --     -- Clear local state; next update_state will decrement counters
    --     state.task_in_progress = nil
    --     state.task_started_at = nil
    --     state.task_meta = nil
    --   end
    -- end


    -- Update scraping window components (enables marquee scrolling in log)
    if scraping_window and scraping_window.visible then
        scraping_window:update(dt)
    end

    -- Periodically write dashboard state for the live server
    if dashboard_server_running and state.scraping then
        dashboard_write_timer = dashboard_write_timer + dt
        if dashboard_write_timer >= 0.5 then
            dashboard_write_timer = 0
            write_dashboard_state()
        end
    end

    -- Trigger initial preview generation ONLY after splash screen is finished
    if not initial_preview_triggered and splash.finished then
        initial_preview_triggered = true
        update_preview(0)
    end
end

function main:draw()
    love.graphics.clear(utils.hex_v(theme:read("main", "BACKGROUND")))
    menu:draw()
    info_window:draw()
    scraping_window:draw()
    draw_core_reminder_popup()

    -- Show status icon: offline icon when in offline mode, wifi icon when disconnected
    local status_icon = nil
    if offline_mode and offline_icon then
        status_icon = offline_icon
    elseif not wifi_connected and wifi_icon then
        status_icon = wifi_icon
    end

    if status_icon then
        local icon_color = theme:read_color("label", "LABEL_TEXT", "#dfe6e9")
        love.graphics.setColor(icon_color)
        local icon_width = 24
        local icon_height = 24
        local margin = 10
        love.graphics.draw(status_icon, w_width - icon_width - margin, margin, 0, icon_width / status_icon:getWidth(),
            icon_height / status_icon:getHeight())
    end

    -- Draw Clock
    if user_config:read("main", "clockEnabled") == "1" then
        local cw, ch = love.window.getMode()
        local format = user_config:read("main", "clockFormat") == "12h" and "%I:%M %p" or "%H:%M"
        local time_str = os.date(format)

        local font = love.graphics.getFont()
        local parts = utils.split(time_str, ":")

        -- Helper for faux-bold
        local function print_bold(text, x, y)
            love.graphics.print(text, x + 1, y)
            love.graphics.print(text, x, y + 1)
            love.graphics.print(text, x + 1, y + 1)
            love.graphics.print(text, x, y)
        end

        local margin = 10
        local colon_pad = 2 -- Extra padding around colon
        local t_width = 0

        if #parts == 2 then
            -- Calculate custom width with padding
            t_width = font:getWidth(parts[1]) + font:getWidth(":") + font:getWidth(parts[2]) + (colon_pad * 2)
        else
            -- Fallback for safety
            t_width = font:getWidth(time_str)
        end

        -- Calculate position (Top-Right)
        local x_pos = cw - t_width - margin
        local y_pos = margin

        -- Shift left if status icon (offline or no-WiFi) is visible
        if (offline_mode and offline_icon) or (not wifi_connected and wifi_icon) then
            x_pos = x_pos - 24 - 10 -- icon_width (24) + padding (10)
        end

        -- Draw text in Accent Color
        love.graphics.setColor(theme:read_color("button", "BUTTON_FOCUS"))

        if #parts == 2 then
            local x_cursor = x_pos
            print_bold(parts[1], x_cursor, y_pos)
            x_cursor = x_cursor + font:getWidth(parts[1]) + colon_pad
            print_bold(":", x_cursor, y_pos)
            x_cursor = x_cursor + font:getWidth(":") + colon_pad
            print_bold(parts[2], x_cursor, y_pos)
        else
            print_bold(time_str, x_pos, y_pos)
        end
    end
end

function main:keypressed(key)
    if key == "escape" then
        if showing_core_reminder then
            showing_core_reminder = false
        elseif info_window.visible then
            info_window.visible = false
            if dashboard_server_running then toggle_dashboard_server() end
        elseif state.scraping then
            halt_scraping()
        else
            love.event.quit()
        end
    end
    if key == "x" and state.scraping then
        toggle_dashboard_server()
    end
    if not state.scraping and not info_window.visible then
        menu:keypressed(key)
    end
    if key == "lalt" then
        scenes:push("settings")
    end
end

function main:gamepadpressed(joystick, button)
    -- Map 'b' button to back/cancel/escape action
    if button == "b" then
        if showing_core_reminder then
            -- User pressed B on the core reminder: save "don't show again"
            user_config:insert("main", "hideCoreReminder", "1")
            user_config:save()
            showing_core_reminder = false
        elseif info_window.visible then
            info_window.visible = false
            if dashboard_server_running then toggle_dashboard_server() end
        elseif state.scraping then
            halt_scraping()
        elseif scraping_window.visible then
            -- Should be covered by state.scraping, but just in case
            scraping_window.visible = false
        else
            love.event.quit()
        end
        return true -- Handled, prevent global input from double-processing
    end

    -- X button: toggle dashboard server during scraping
    if button == "x" and state.scraping then
        toggle_dashboard_server()
        return true
    end

    if not state.scraping and not info_window.visible and not showing_core_reminder then
        if menu.gamepadpressed then
            menu:gamepadpressed(joystick, button)
        end
    elseif showing_core_reminder and button == "a" then
        -- A button just dismisses the popup (no "don't show again")
        showing_core_reminder = false
    elseif info_window.visible and button == "a" then
        info_window.visible = false
        return true
    end
    return false -- Let global input handle D-pad navigation
end

function main:resume()
    -- Form a fresh preview generation request to clear out the one Template Maker just made
    update_preview(0)

    local current_scraper = user_config:read("main", "scraperModule") or "screenscraper"
    local warning = menu ^ "ss_warning"

    if skyscraper_config:has_credentials(current_scraper) then
        -- If we have credentials now, remove the warning if it exists
        if warning then
            -- Find and remove the warning component
            for i, child in ipairs(menu.children) do
                if child.id == "ss_warning" then
                    table.remove(menu.children, i)
                    break
                end
            end
            -- Recalculate layout
            menu:updatePosition(10, 10)
        end
    else
        -- If we don't have credentials, we need to show the correct warning
        local warn_text = current_scraper == "thegamesdb" 
            and "TheGamesDB scraping is limited without an API key. Add it in Settings."
            or "Open Settings and add your ScreenScraper credentials."
            
        if warning then
            if warning.text ~= warn_text then
                warning.text = warn_text
            end
        else
            menu = menu + label {
                id = "ss_warning",
                text = warn_text,
                icon = "warn",
                max_width = w_width * 0.95
            }
            menu:updatePosition(10, 10)
        end
    end
end

return main
