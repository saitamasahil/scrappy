local scenes = require("lib.scenes")
local skyscraper = require("lib.skyscraper")
local pprint = require("lib.pprint")
local log = require("lib.log")
local channels = require("lib.backend.channels")
local configs = require("helpers.config")
local utils = require("helpers.utils")
local artwork = require("helpers.artwork")
local muos = require("helpers.muos")
local wifi = require("helpers.wifi")

local component = require 'lib.gui.badr'
local label = require 'lib.gui.label'
local popup = require 'lib.gui.popup'
local listitem = require 'lib.gui.listitem'
local checkbox = require 'lib.gui.checkbox'
local scroll_container = require 'lib.gui.scroll_container'
local output_log = require 'lib.gui.output_log'
local icon = require 'lib.gui.icon'
local virtual_keyboard = require 'lib.gui.virtual_keyboard'

local w_width, w_height = love.window.getMode()
local single_scrape = {}

local menu, info_window, scraping_window, platform_list, rom_list, rom_scroll, footer
local user_config = configs.user_config
local skyscraper_config = configs.skyscraper_config
local theme = configs.theme

local last_selected_platform = nil
local last_selected_rom = nil
local focused_rom = nil -- Tracks currently focused ROM for X button manual scraping
local active_column = 1 -- 1 for platforms, 2 for ROMs
local show_missing_only = false
local missing_filter_item = nil

local state = {
    scraping = false,
    fetch_stage = false,
    generate_stage = false,
    manual_mode = false,
    current_game = nil,
    current_platform = nil,
    log = {},
    -- Refine search state
    refine_search_active = false,
    refine_query = "",
    last_failed_rom = nil,
    last_failed_platform = nil,
    refine_attempted = false, -- Track if we've already tried a refine search
    refine_confirm_visible = false, -- Confirmation popup before showing VK
    refine_fade = 0
}

-- Virtual keyboard for refine search
local vk = nil

-- Load button icons for confirmation popup
local button_a_icon = nil
local button_b_icon = nil
pcall(function()
    button_a_icon = love.graphics.newImage("assets/inputs/switch_button_a.png")
end)
pcall(function()
    button_b_icon = love.graphics.newImage("assets/inputs/switch_button_b.png")
end)

local function halt_scraping()
    log.write("[single_scrape] Halting scraping operation")
    channels.SKYSCRAPER_ABORT:push({
        abort = true
    })

    -- Forcefully kill any running Skyscraper processes immediately
    os.execute("killall -9 Skyscraper Skyscraper.aarch64 2>/dev/null")

    -- Give threads a moment to process abort signal
    love.timer.sleep(0.2)

    -- Clear all channels to prevent stale data
    channels.SKYSCRAPER_INPUT:clear()
    channels.SKYSCRAPER_GEN_INPUT:clear()
    channels.SKYSCRAPER_GAME_QUEUE:clear()
    channels.SKYSCRAPER_OUTPUT:clear()
    channels.SKYSCRAPER_GEN_OUTPUT:clear()
    while channels.SKYSCRAPER_ABORT:pop() do
    end -- Clear abort signals

    -- Restart threads to ensure clean state
    skyscraper.restart_threads()

    state.scraping = false
    state.fetch_stage = false
    state.generate_stage = false
    state.manual_mode = false
    state.current_game = nil
    state.current_platform = nil
    state.log = {}

    if scraping_window then
        scraping_window.visible = false
        -- Clear the log display
        local scraping_log = scraping_window ^ "scraping_log"
        if scraping_log then
            scraping_log.text = ""
        end
    end

    log.write("[single_scrape] Scraping halted and state cleared")

    -- Also reset refine search state
    state.refine_search_active = false
    state.refine_query = ""
    state.last_failed_rom = nil
    state.last_failed_platform = nil
    if vk then
        vk.visible = false
    end
end

-- Handle refine search submission from virtual keyboard
local function on_refine_search_done(query, target)
    if not query or query == "" then
        -- Empty query, treat as cancel
        state.refine_search_active = false
        return
    end

    state.refine_query = query
    state.refine_search_active = false

    -- Retry scraping with the custom query
    local rom = state.last_failed_rom
    local platform_dest = state.last_failed_platform

    if not rom or not platform_dest then
        log.write("[single_scrape] Refine search failed: missing ROM or platform info")
        return
    end

    local rom_path, _ = user_config:get_paths()
    rom_path = string.format("%s/%s", rom_path, last_selected_platform)

    log.write(string.format("[single_scrape] Retrying scrape with query: %s", query))

    -- Clear any stale abort signals
    while channels.SKYSCRAPER_ABORT:pop() do
    end

    state.scraping = true
    state.fetch_stage = true
    state.generate_stage = false
    state.current_game = utils.get_filename(rom)
    state.current_platform = platform_dest
    state.log = {}

    if scraping_window then
        local ui_platform = scraping_window ^ "platform"
        local ui_game = scraping_window ^ "game"
        local ui_status = scraping_window ^ "status"
        if ui_platform then
            ui_platform.text = muos.platforms[platform_dest] or platform_dest or "N/A"
        end
        if ui_game then
            ui_game.text = state.current_game .. " (refine: " .. query .. ")"
        end
        if ui_status then
            ui_status.text = "Fetching from server..."
        end
        local ui_source = scraping_window ^ "scraper_source"
        if ui_source then
            local module = skyscraper.get_module_name(platform_dest or state.last_failed_platform)
            local module_map = {
                screenscraper = "ScreenScraper",
                thegamesdb = "TheGamesDB",
                import = "Import"
            }
            ui_source.text = string.format("Source: %s", module_map[module] or module or "N/A")
        end
        scraping_window.visible = true
        scraping_window.fade = 0
    end

    -- Mark that we've attempted a refine search
    state.refine_attempted = true

    -- Call fetch_single with custom query
    if state.manual_mode then
        skyscraper.fetch_single_manual(rom_path, rom, last_selected_platform, platform_dest, query)
    else
        skyscraper.fetch_single(rom_path, rom, last_selected_platform, platform_dest, {"unattend"}, query)
    end
end

local function on_refine_search_cancel(target)
    state.refine_search_active = false
    state.last_failed_rom = nil
    state.last_failed_platform = nil
    state.refine_attempted = false
end

local function show_refine_search(rom, platform)
    state.refine_search_active = true
    state.refine_confirm_visible = false

    -- Use filename without extension as initial search term
    local initial_query = utils.get_filename(rom) or ""

    if not vk then
        vk = virtual_keyboard.create({
            on_done = on_refine_search_done,
            on_cancel = on_refine_search_cancel,
            placeholder = "Enter game name...",
            title = "Refine Search"
        })
    end

    vk:show(initial_query, "refine")
end

-- Show confirmation popup asking if user wants to refine search
local function show_refine_confirm(rom, platform)
    state.last_failed_rom = rom
    state.last_failed_platform = platform
    state.refine_confirm_visible = true
    state.refine_fade = 0 -- Explicit reset
end

-- User confirmed they want to refine search
local function on_confirm_refine()
    state.refine_confirm_visible = false
    show_refine_search(state.last_failed_rom, state.last_failed_platform)
end

-- User declined refine search
local function on_cancel_refine()
    state.refine_confirm_visible = false
    state.last_failed_rom = nil
    state.last_failed_platform = nil
    state.refine_attempted = false
end

local function stop_refining()
    state.refine_confirm_visible = false
end

-- Draw the refine search confirmation popup
local function draw_refine_confirm_popup()
    if not state.refine_confirm_visible then
        state.refine_fade = 0
        return
    end

    state.refine_fade = state.refine_fade + (1 - state.refine_fade) * 20 * love.timer.getDelta()
    if state.refine_fade > 0.999 then state.refine_fade = 1 end

    local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
    local font = love.graphics.getFont()
    local font_h = font:getHeight()

    love.graphics.push()
    love.graphics.origin()

    -- Dim background
    love.graphics.setColor(0, 0, 0, 0.8 * state.refine_fade)
    love.graphics.rectangle("fill", 0, 0, sw, sh)

    local popup_scale = 0.85 + 0.15 * state.refine_fade
    love.graphics.translate(sw / 2, sh / 2)
    love.graphics.scale(popup_scale, popup_scale)
    love.graphics.translate(-sw / 2, -sh / 2)

    -- Popup box dimensions
    local box_w = math.min(sw - 40, 340)
    local box_h = 130
    local box_x = (sw - box_w) / 2
    local box_y = (sh - box_h) / 2

    -- Draw box background
    love.graphics.setColor(0.18, 0.18, 0.18, 1)
    love.graphics.rectangle("fill", box_x, box_y, box_w, box_h, 8, 8)

    -- Draw border
    love.graphics.setColor(0.4, 0.4, 0.4, 1)
    love.graphics.rectangle("line", box_x, box_y, box_w, box_h, 8, 8)

    love.graphics.setColor(1, 1, 1, 1)

    -- Title
    love.graphics.printf("Game Not Found", box_x, box_y + 12, box_w, "center")

    -- Message
    local msg = "Would you like to refine your search?"
    love.graphics.printf(msg, box_x + 15, box_y + 40, box_w - 30, "center")

    -- Button icons and labels
    local icon_size = 24
    local btn_y = box_y + box_h - 38

    local left_center = box_x + box_w * 0.25
    local right_center = box_x + box_w * 0.75

    -- Yes button (A)
    local yes_total_w = icon_size + 6 + font:getWidth("Yes")
    local yes_x = left_center - yes_total_w / 2
    if button_a_icon then
        local iw, ih = button_a_icon:getDimensions()
        local sx, sy = icon_size / iw, icon_size / ih
        love.graphics.draw(button_a_icon, yes_x, btn_y, 0, sx, sy)
    end
    love.graphics.print("Yes", yes_x + icon_size + 6, btn_y + (icon_size - font_h) / 2)

    -- No button (B)
    local no_total_w = icon_size + 6 + font:getWidth("No")
    local no_x = right_center - no_total_w / 2
    if button_b_icon then
        local iw, ih = button_b_icon:getDimensions()
        local sx, sy = icon_size / iw, icon_size / ih
        love.graphics.draw(button_b_icon, no_x, btn_y, 0, sx, sy)
    end
    love.graphics.print("No", no_x + icon_size + 6, btn_y + (icon_size - font_h) / 2)

    love.graphics.pop()
end

local function set_rom_list_enabled(enabled)
    if not rom_list or not rom_list.children then
        return
    end
    for _, item in ipairs(rom_list.children) do
        item.disabled = not enabled
    end
    if enabled then
        rom_list:focusFirstElement()
    end
end

local function get_required_output_types()
    local p = artwork.get_artwork_path()
    if not p then
        return {
            box = true,
            preview = true,
            splash = true
        }
    end
    local output_types = artwork.get_output_types(p)
    if not output_types then
        return {
            box = true,
            preview = true,
            splash = true
        }
    end
    -- If the template declares no outputs, fall back to requiring boxart
    if not output_types.box and not output_types.preview and not output_types.splash then
        return {
            box = true,
            preview = false,
            splash = false
        }
    end
    return output_types
end

local function has_missing_media(dest_platform, rom)
    if not dest_platform or not rom then
        return false
    end
    local game_title = utils.get_filename(rom)
    if not game_title or game_title == "" then
        return false
    end
    local _, catalogue_path = user_config:get_paths()
    if not catalogue_path or catalogue_path == "" then
        return true
    end
    local platform_str = muos.platforms[dest_platform] or dest_platform
    local base = string.format("%s/%s", catalogue_path, platform_str)
    local required = get_required_output_types()

    local function missing_for(output_type)
        local fp = string.format("%s/%s/%s.png", base, output_type, game_title)
        return nativefs.getInfo(fp) == nil
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

local function toggle_info()
    info_window.visible = not info_window.visible
end
local function dispatch_info(title, content)
    info_window.title = title
    info_window.content = content
end

local function on_select_platform(platform)
    last_selected_platform = platform
    active_column = 2
    for _, item in ipairs(platform_list.children) do
        item.disabled = true
        item.active = item.id == platform
    end
    set_rom_list_enabled(true)
end

local function on_rom_press(rom)
    last_selected_rom = rom
    local rom_path, _ = user_config:get_paths()
    local platforms = user_config:get().platforms

    rom_path = string.format("%s/%s", rom_path, last_selected_platform)

    -- Check if offline mode is enabled - single scrape always fetches new data
    local offline_mode = (user_config:read("main", "offlineMode") == "1")
    if offline_mode then
        dispatch_info("Offline Mode Active",
            "Single ROM scraping requires internet to fetch new data. Please disable Offline Mode in Advanced Tools.")
        toggle_info()
        return
    end

    -- Check WiFi connection before scraping
    if not wifi.is_connected() then
        dispatch_info("No WiFi Connection", "Please connect to WiFi and try again.")
        toggle_info()
        return
    end

    local artwork_name = artwork.get_artwork_name()

    if artwork_name then
        local platform_dest = platforms[last_selected_platform]
        -- Prevent running Skyscraper with an unmapped platform
        if not platform_dest or platform_dest == "unmapped" then
            dispatch_info("Error",
                "Selected platform is not mapped to a muOS core. Open Settings and rescan/assign cores.")
            toggle_info()
        else
            -- Clear any stale abort signals before starting
            while channels.SKYSCRAPER_ABORT:pop() do
            end

            log.write(string.format("[single_scrape] Starting scrape for ROM: %s", rom))
            log.write(string.format("[single_scrape] Platform: %s -> %s", last_selected_platform, platform_dest))
            log.write(string.format("[single_scrape] ROM path: %s", rom_path))

            state.scraping = true
            state.fetch_stage = true
            state.generate_stage = false
            state.current_game = utils.get_filename(rom)
            state.current_platform = platform_dest
            state.log = {}

            if scraping_window then
                local ui_platform = scraping_window ^ "platform"
                local ui_game = scraping_window ^ "game"
                local ui_status = scraping_window ^ "status"
                if ui_platform then
                    ui_platform.text = muos.platforms[platform_dest] or platform_dest or "N/A"
                end
                if ui_game then
                    ui_game.text = state.current_game or "N/A"
                end
                if ui_status then
                    ui_status.text = "Fetching from server..."
                end
                local ui_source = scraping_window ^ "scraper_source"
                if ui_source then
                    local module = skyscraper.get_module_name(platform_dest)
                    local module_map = {
                        screenscraper = "ScreenScraper",
                        thegamesdb = "TheGamesDB",
                        import = "Import"
                    }
                    ui_source.text = string.format("Source: %s", module_map[module] or module or "N/A")
                end
                scraping_window.visible = true
                scraping_window.fade = 0
            end

            -- Clear local artwork cache before starting the fetch so old media is removed
            local cache_path = skyscraper_config:read("main", "cacheFolder")
            cache_path = utils.strip_quotes(cache_path or "")
            if cache_path == "" then
                cache_path = WORK_DIR .. "/data/cache"
            end
            local script_path = WORK_DIR .. "/scripts/clear_local_cache.py"
            if nativefs.getInfo(script_path) then
                local rom_escaped = rom:gsub('\\', '\\\\'):gsub('"', '\\"')
                os.execute(string.format('python3 "%s" --cache "%s" --platform "%s" --rom "%s" 2>/dev/null',
                    script_path, cache_path, platform_dest, rom_escaped))
            end

            skyscraper.fetch_single(rom_path, rom, last_selected_platform, platform_dest)
        end
    else
        dispatch_info("Error", "Artwork XML not found")
        toggle_info()
    end
end

local function on_manual_scrape(rom)
    last_selected_rom = rom
    local rom_path, _ = user_config:get_paths()
    local platforms = user_config:get().platforms

    rom_path = string.format("%s/%s", rom_path, last_selected_platform)

    -- Check if offline mode is enabled
    local offline_mode = (user_config:read("main", "offlineMode") == "1")
    if offline_mode then
        dispatch_info("Offline Mode Active",
            "Scraping game manuals requires an internet connection. Please disable Offline Mode in Advanced Tools.")
        toggle_info()
        return
    end

    -- Check WiFi
    if not wifi.is_connected() then
        dispatch_info("No WiFi Connection", "Please connect to WiFi and try again.")
        toggle_info()
        return
    end

    local platform_dest = platforms[last_selected_platform]
    if not platform_dest or platform_dest == "unmapped" then
        dispatch_info("Error",
            "Selected platform is not mapped to a muOS core. Open Settings and rescan/assign cores.")
        toggle_info()
        return
    end

    -- Clear stale abort signals
    while channels.SKYSCRAPER_ABORT:pop() do
    end

    log.write(string.format("[single_scrape] Starting manual scrape for ROM: %s", rom))

    state.scraping = true
    state.fetch_stage = true
    state.generate_stage = false
    state.manual_mode = true
    state.current_game = utils.get_filename(rom)
    state.current_platform = platform_dest
    state.log = {}

    if scraping_window then
        local ui_platform = scraping_window ^ "platform"
        local ui_game = scraping_window ^ "game"
        local ui_status = scraping_window ^ "status"
        if ui_platform then
            ui_platform.text = muos.platforms[platform_dest] or platform_dest or "N/A"
        end
        if ui_game then
            ui_game.text = state.current_game or "N/A"
        end
        if ui_status then
            ui_status.text = "Fetching manual..."
        end
        local ui_source = scraping_window ^ "scraper_source"
        if ui_source then
            ui_source.text = "Source: ScreenScraper"
        end
        scraping_window.visible = true
        scraping_window.fade = 0
    end

    skyscraper.fetch_single_manual(rom_path, rom, last_selected_platform, platform_dest)
end

local function on_return()
    if info_window.visible then
        toggle_info()
        return
    end
    if active_column == 2 then
        active_column = 1
        for _, item in ipairs(platform_list.children) do
            item.disabled = false
            item.active = false
        end
        set_rom_list_enabled(false)
        local active_element = platform_list % last_selected_platform
        platform_list:setFocus(active_element)
    else
        scenes:pop()
    end
end

local function load_rom_buttons(src_platform, dest_platform)
    -- If focus is currently inside the rom_list, we should back it out 
    -- before clearing children to avoid 'ghost' focus state.
    if menu then
        local focused = menu.focusedElement
        if focused and focused.parent == rom_list then
            -- Focus a safe non-disabled element (first platform or menu root)
            local safe_target = platform_list and platform_list.children and platform_list.children[1]
            menu:setFocus(safe_target or menu)
        end
    end

    rom_list.children = {} -- Clear existing ROM items
    rom_list.height = 0   -- Reset height so it can shrink
    -- Store them for toggle refresh
    last_selected_platform = src_platform
    last_dest_platform = dest_platform

    -- Set label
    local label_item = menu ^ "roms_label"
    if label_item then
        label_item.text = string.format("%s (%s)", src_platform, dest_platform)
    end

    local rom_path, _ = user_config:get_paths()
    local platform_path = string.format("%s/%s", rom_path, src_platform)
    local roms = nativefs.getDirectoryItems(platform_path)

    for _, rom in ipairs(roms) do
        local file_path = string.format("%s/%s", platform_path, rom)
        local file_info = nativefs.getInfo(file_path)
        -- Skip if file info could not be retrieved
        if not file_info then
            goto continue
        end

        if file_info.type == "file" then
            if show_missing_only and not has_missing_media(dest_platform, rom) then
                goto continue
            end
            -- Green (2) if artwork exists, Red (3) if missing
            local has_artwork = not has_missing_media(dest_platform, rom)
            rom_list = rom_list + listitem {
                id = rom, -- Add id for lookup after scraping
                text = rom,
                width = ((w_width - 30) / 3) * 2,
                onClick = function()
                    on_rom_press(rom)
                end,
                onFocus = function()
                    focused_rom = rom
                end,
                disabled = true,
                active = true,
                indicator = has_artwork and 2 or 3
            }
        end
        ::continue::
    end

    -- IMPORTANT: Reset scroll position to top AFTER filling the list
    -- This ensures clamping works with the new height
    if rom_scroll then
        rom_scroll:scrollTo(0)
    end
end

local function toggle_missing_filter(checked)
    local now = love.timer.getTime()
    show_missing_only = (checked == true)
    print(string.format("[DEBUG] [%.2f] toggle_missing_filter: %s", now, tostring(show_missing_only)))
    
    if missing_filter_item then
        -- Sync the internal state only if it doesn't match
        if missing_filter_item.checked ~= show_missing_only then
            missing_filter_item.checked = show_missing_only
        end
        local statusText = show_missing_only and "ON" or "OFF"
        missing_filter_item.text = string.format("Show only missing artwork: %s", statusText)
    end

    -- Persist to config
    user_config:insert("main", "showMissingOnly", show_missing_only and "1" or "0")
    user_config:save()

    local plat = last_selected_platform
    local dest = last_dest_platform
    
    -- Fallback: check platform_list
    if not plat and platform_list then
        for _, item in ipairs(platform_list.children) do
            if item.active then
                plat = item.id
                local platforms = user_config:get().platforms
                dest = platforms and platforms[plat]
                break
            end
        end
    end

    if plat and dest and dest ~= "unmapped" then
        -- Refresh the list and enable ROM items
        load_rom_buttons(plat, dest)
        for _, item in ipairs(rom_list.children) do
            item.disabled = false
        end
        -- Only change focus if user is in the ROM column
        if active_column == 2 then
            if rom_list.children and #rom_list.children > 0 then
                rom_list:focusFirstElement()
            else
                -- No ROMs match filter — return to platform column
                active_column = 1
                for _, item in ipairs(platform_list.children) do
                    item.disabled = false
                    item.active = (item.id == plat)
                end
                local active_element = platform_list % plat
                if active_element then
                    platform_list:setFocus(active_element)
                else
                    platform_list:focusFirstElement()
                end
            end
        end
    end
end

local function load_platform_buttons()
    platform_list.children = {} -- Clear existing platforms
    platform_list.height = 0

    local platforms = user_config:get().platforms

    for src, dest in utils.orderedPairs(platforms or {}) do
        platform_list = platform_list + listitem {
            id = src,
            text = src,
            width = ((w_width - 30) / 3),
            onFocus = function()
                load_rom_buttons(src, dest)
            end,
            onClick = function()
                on_select_platform(src)
            end,
            disabled = false
        }
    end
end

local function process_fetched_game()
    local t = channels.SKYSCRAPER_GAME_QUEUE:pop()
    if t then
        if t.skipped then
            state.scraping = false
            state.fetch_stage = false
            scraping_window.visible = false

            -- Check if we've already tried a refine search
            if state.refine_attempted then
                -- Refine search also failed - show error message instead of looping
                log.write("[single_scrape] Refine search also failed, showing error")
                state.refine_attempted = false
                state.last_failed_rom = nil
                state.last_failed_platform = nil
                dispatch_info("Game Not Found",
                    "Could not find game even with refined search. Try a different search term or check if the game exists in ScreenScraper/TheGamesDB database.")
                toggle_info()
                return
            end

            -- First failure - show confirmation popup asking if user wants to refine search
            log.write("[single_scrape] Game not found or match too low, showing refine confirmation")
            local platforms = user_config:get().platforms
            local platform_dest = platforms and platforms[last_selected_platform]
            show_refine_confirm(last_selected_rom, platform_dest)
            return
        end

        state.fetch_stage = false
        state.refine_attempted = false -- Reset on successful scrape

        -- Clear local artwork cache so only the newly scraped source exists
        local cache_path = skyscraper_config:read("main", "cacheFolder")
        cache_path = utils.strip_quotes(cache_path or "")
        if cache_path == "" then
            cache_path = WORK_DIR .. "/data/cache"
        end
        local script_path = WORK_DIR .. "/scripts/clear_local_cache.py"
        if nativefs.getInfo(script_path) then
            local rom_escaped = last_selected_rom:gsub('\\', '\\\\'):gsub('"', '\\"')
            os.execute(string.format('python3 "%s" --cache "%s" --platform "%s" --rom "%s" 2>/dev/null',
                script_path, cache_path, t.platform, rom_escaped))
        end

        -- Manual mode: extract PDF from cache and finish (no artwork generation)
        if state.manual_mode then
            local ui_status = scraping_window ^ "status"
            if ui_status then
                ui_status.text = "Extracting manual..."
            end

            local copied, skipped = artwork.extract_manuals(t.platform)

            state.scraping = false
            state.manual_mode = false
            scraping_window.visible = false
            state.log = {}

            if copied > 0 then
                dispatch_info("Manual Downloaded", string.format("Game manual saved for %s.\n Use KOReader via PortMaster to read it.", state.current_game))
            elseif skipped > 0 then
                dispatch_info("Manual Exists", string.format("Manual already exists for %s.", state.current_game))
            else
                dispatch_info("No Manual Found", string.format("No manual available for %s on ScreenScraper.", state.current_game))
            end
            toggle_info()
            return
        end

        state.generate_stage = true

        local ui_status = scraping_window ^ "status"
        if ui_status then
            ui_status.text = "Generating artwork..."
        end

        local rom_path, _ = user_config:get_paths()
        rom_path = string.format("%s/%s", rom_path, last_selected_platform)
        local artwork_name = artwork.get_artwork_name()
        skyscraper.update_artwork(rom_path, last_selected_rom, t.input_folder, t.platform, artwork_name)
    end
end

local function update_scrape_state()
    local t = channels.SKYSCRAPER_OUTPUT:pop()
    if t then
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
            if scraping_log then
                scraping_log.text = log_str
            end
        end

        if t.error and t.error ~= "" then
            state.scraping = false
            state.fetch_stage = false
            state.generate_stage = false
            scraping_window.visible = false
            dispatch_info("Error", t.error)
            toggle_info()
        end

        local ui_source = scraping_window ^ "scraper_source"
        if ui_source then
            if state.fetch_stage then
                local module = skyscraper.get_module_name(state.current_platform)
                local module_map = {
                    screenscraper = "ScreenScraper",
                    thegamesdb = "TheGamesDB",
                    import = "Import"
                }
                ui_source.text = string.format("Source: %s", module_map[module] or module or "N/A")
            elseif state.generate_stage then
                ui_source.text = "Source: Local"
            end
        end

        if t.title then
            state.scraping = false
            state.fetch_stage = false
            state.generate_stage = false
            scraping_window.visible = false
            state.log = {}

            dispatch_info("Finished", t.success and "Scraping finished successfully" or "Scraping failed or skipped")
            toggle_info()

            if t.success then
                artwork.copy_to_catalogue(t.platform, t.title)
                artwork.process_cached_by_platform(t.platform)
                -- Reload ROM buttons with proper platform mapping to refresh artwork indicators
                local platforms = user_config:get().platforms
                local dest_platform = platforms and platforms[last_selected_platform]
                if dest_platform then
                    load_rom_buttons(last_selected_platform, dest_platform)
                    -- Re-enable the ROM list after reloading
                    set_rom_list_enabled(true)
                    -- Focus on the last scraped ROM instead of first element
                    if last_selected_rom and rom_list then
                        local target_item = rom_list % last_selected_rom
                        if target_item then
                            rom_list:setFocus(target_item)
                        else
                            rom_list:focusFirstElement()
                        end
                    else
                        rom_list:focusFirstElement()
                    end
                end
            end
        end
    end
end

function single_scrape:load()
    -- Clear UI output channel
    channels.TASK_OUTPUT:clear()

    -- Restart threads to ensure clean state after any previous scraping
    skyscraper.restart_threads()
    log.write("[single_scrape] Loaded - threads restarted")

    last_selected_platform = nil
    last_selected_rom = nil
    focused_rom = nil
    active_column = 1
    -- Restore persisted setting
    show_missing_only = (user_config:read("main", "showMissingOnly") == "1")
    missing_filter_item = nil

    state.scraping = false
    state.fetch_stage = false
    state.generate_stage = false
    state.current_game = nil
    state.current_platform = nil
    state.log = {}

    if utils.table_length(artwork.cached_game_ids) == 0 then
        artwork.process_cached_data()
    end

    menu = component:root{
        column = true,
        gap = 0
    }

    info_window = popup {
        visible = false
    }
    scraping_window = popup {
        visible = false,
        title = "Scraping in progress"
    }
    platform_list = component {
        column = true,
        gap = 0
    }
    rom_list = component {
        column = true,
        gap = 0
    }

    load_platform_buttons()

    local left_column = component {
        column = true,
        gap = 10
    } + label {
        text = 'Platforms',
        icon = "folder"
    } + (scroll_container {
        width = (w_width - 30) / 3,
        height = w_height - 100, -- Reduced to prevent footer overlap (was -60)
        scroll_speed = 30
    } + platform_list)

    -- Create scroll container for ROMs so we can control it (reset scroll)
    rom_scroll = scroll_container {
        width = ((w_width - 30) / 3) * 2,
        height = w_height - 150, -- Reduced to prevent footer overlap (was -110)
        scroll_speed = 30
    }

    local right_column = component {
        column = true,
        gap = 10
    } + label {
        id = "roms_label",
        text = 'ROMs',
        icon = "cd"
    } + (checkbox {
        id = "missing_filter",
        icon = "button_y",
        iconSize = 22,
        text = string.format("Show only missing artwork: %s", show_missing_only and "ON" or "OFF"),
        onToggle = toggle_missing_filter,
        checked = show_missing_only,
        focusable = false,
    }) + (rom_scroll + rom_list)

    missing_filter_item = right_column % "missing_filter"

    menu = menu + (component {
        row = true,
        gap = 10
    } + left_column + right_column)

    menu:updatePosition(10, 10)
    menu:focusFirstElement()

    -- Create footer with button hints
    footer = component { row = true, gap = 40 }
        + label { id = "footer_a", text = "Select", icon = "button_a" }
        + label { id = "footer_b", text = "Back", icon = "button_b" }
        + label { id = "footer_x", text = "Get Manual", icon = "button_x" }
        + label { id = "footer_dpad", text = "Navigate", icon = "dpad" }
        + label { id = "footer_select", text = "Settings", icon = "select" }
    footer:updatePosition(w_width * 0.5 - footer.width * 0.5 - 20, w_height - footer.height - 10)

    -- Setup scraping window
    local infoComponent = component {
        column = true,
        gap = 10,
        width = love.graphics.getWidth() * 0.85
    } + label {
        id = "platform",
        text = "Platform: N/A",
        icon = "controller",
        max_width = love.graphics.getWidth() * 0.85
    } + label {
        id = "game",
        text = "Game: N/A",
        icon = "cd",
        max_width = love.graphics.getWidth() * 0.85
    } + label {
        id = "status",
        text = "Status: N/A",
        icon = "info",
        max_width = love.graphics.getWidth() * 0.85
    } + label {
        id = "scraper_source",
        text = "Source: N/A",
        icon = "source",
        max_width = love.graphics.getWidth() * 0.85
    }

    scraping_window = scraping_window + (component {
        column = true,
        gap = 15,
        width = love.graphics.getWidth() * 0.85
    } + infoComponent + output_log {
        id = "scraping_log",
        width = love.graphics.getWidth() * 0.85,
        height = 100
    })
end

function single_scrape:update(dt)
    menu:update(dt)
    if footer then footer:update(dt) end
    update_scrape_state()
    process_fetched_game()

    -- Update scraping window components (enables marquee scrolling in log)
    if scraping_window and scraping_window.visible then
        scraping_window:update(dt)
    end

    -- Update virtual keyboard if active
    if vk and vk.visible then
        vk:update(dt)
    end
end

function single_scrape:draw()
    love.graphics.clear(theme:read_color("main", "BACKGROUND", "#000000"))
    menu:draw()
    info_window:draw()
    scraping_window:draw()

    -- Draw confirmation popup on top
    draw_refine_confirm_popup()

    -- Draw footer (hidden during VK, scraping, or info overlays)
    if footer and not (vk and vk.visible) and not scraping_window.visible and not info_window.visible then
        footer:draw()
    end

    -- Draw virtual keyboard on top of everything
    if vk and vk.visible then
        vk:draw()
    end
end

function single_scrape:keypressed(key)
    -- Handle virtual keyboard input first if visible (highest priority)
    if vk and vk.visible then
        local mapped = nil
        if key == 'up' or key == 'down' or key == 'left' or key == 'right' then
            mapped = key
        end
        if key == 'return' then
            mapped = 'confirm'
        end
        if key == 'escape' then
            mapped = 'cancel'
        end
        if key == 'backspace' then mapped = 'backspace' end
        if key == 'x' then mapped = 'x' end
        if key == 'y' then mapped = 'y' end
        if key == 'space' then mapped = 'space' end
        
        if mapped then
            vk:handle_key(mapped)
            return
        end
        return
    end

    -- Handle info popup first (highest priority)
    if info_window.visible then
        if key == "escape" or key == "return" or key == "a" or key == "b" then
            toggle_info()
            return
        end
        return -- Block all other keys
    end

    -- Handle confirmation popup
    if state.refine_confirm_visible then
        if key == 'return' or key == 'a' then
            on_confirm_refine()
            return
        elseif key == 'escape' or key == 'b' then
            on_cancel_refine()
            return
        end
        return -- Block all other keys while popup is visible
    end

    if key == "escape" then
        if state.scraping then
            halt_scraping()
            return
        end
        on_return()
        return
    end

    if not state.scraping then
        menu:keypressed(key)
    end

    if key == "lalt" and not state.scraping then
        scenes:push("settings")
    end

    -- Y button for global filter toggle
    if key == "y" and not state.scraping and (active_column == 2 or last_selected_platform) then
        toggle_missing_filter(not show_missing_only)
    end

    -- X button for manual scraping
    if key == "x" and not state.scraping and active_column == 2 and focused_rom then
        on_manual_scrape(focused_rom)
    end
end

function single_scrape:gamepadpressed(joystick, button)
    -- Handle info popup first
    if info_window.visible then
        if button == "a" or button == "b" then
            toggle_info()
            return true
        end
        return true -- Block all other buttons
    end

    -- Handle confirmation popup first
    if state.refine_confirm_visible then
        if button == 'a' then
            on_confirm_refine()
            return true
        elseif button == 'b' then
            on_cancel_refine()
            return true
        end
        return true -- Block all other buttons while popup is visible
    end

    -- Handle virtual keyboard input first if visible
    if vk and vk.visible then
        local map = {
            dpup = 'up',
            dpdown = 'down',
            dpleft = 'left',
            dpright = 'right',
            a = 'confirm',
            b = 'cancel',
            x = 'x',
            y = 'y'
        }
        local btn = type(button) == 'string' and button:lower() or button
        local m = map[btn] or map[button]
        if m then
            if m == 'up' or m == 'down' or m == 'left' or m == 'right' then
                -- D-pad handled in update for hold repeat
                return true
            end
            vk:handle_key(m)
            return true
        end
        return true
    end

    -- Map 'b' button to abort/back action
    if button == "b" then
        if state.scraping then
            halt_scraping()
            return true -- Handled, don't let global input also process
        end
        on_return()
        return true -- Handled, don't let global input also process
    end

    if not state.scraping then
        if menu.gamepadpressed then
            menu:gamepadpressed(joystick, button)
        end
        -- X button for manual scraping
        if button == "x" and active_column == 2 and focused_rom then
            on_manual_scrape(focused_rom)
            return true
        end
        -- Y button for global filter toggle
        if button == "y" and (active_column == 2 or last_selected_platform) then
            toggle_missing_filter(not show_missing_only)
            return true
        end
    end
    return false -- Not handled by VK or B button, allow global input
end

return single_scrape
