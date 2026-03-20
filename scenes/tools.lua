local log = require("lib.log")
local json = require("lib.json")
local pprint = require("lib.pprint")
local scenes = require("lib.scenes")
local skyscraper = require("lib.skyscraper")
local channels = require("lib.backend.channels")
local configs = require("helpers.config")
local artwork = require("helpers.artwork")
local utils = require("helpers.utils")

local component = require 'lib.gui.badr'
local popup = require 'lib.gui.popup'
local listitem = require 'lib.gui.listitem'
local scroll_container = require 'lib.gui.scroll_container'
local output_log = require 'lib.gui.output_log'
local label = require 'lib.gui.label'
local icon = require 'lib.gui.icon'
local virtual_keyboard = require 'lib.gui.virtual_keyboard'

local tools = {}
local theme = configs.theme
local scraper_opts = {"screenscraper", "thegamesdb"}
local scraper_index = 1
local theme_opts = {"dark", "light"}
local theme_index = 1
local muos_accent = true -- legacy (derived from accent_mode)

local accent_mode = "muos" -- off | muos | custom
local custom_accent = "cbaa0f"
local offline_mode = false -- Offline mode setting
local vk = nil

local w_width, w_height = love.window.getMode()

local menu, info_window, footer
local user_config, skyscraper_config

local dispatch_info

local region_popup, region_menu, region_list
local confirm_popup, confirm_popup_visible = nil, false
local clear_cache_popup_visible = false
local offline_popup_visible = false -- Offline mode confirmation popup
local confirm_fade, clear_cache_fade, offline_fade = 0, 0, 0 -- Zoom animation state
local accent_popup, accent_menu
local artwork_manager_running = false
local artwork_manager_ip = nil
local artwork_manager_status = ""
local REGEN_FILE = "/tmp/scrappy_regen.json"
local regen_check_timer = 0
local template_maker_running = false
local template_maker_ip = nil
local template_maker_status = ""
local TPL_REGEN_FILE = "/tmp/scrappy_tpl_regen.json"
local tpl_regen_check_timer = 0
local pending_region_prios = nil
local selected_region_index = 1
local region_prios = {}
local default_region_prios = {"us", "wor", "eu", "jp", "ss", "uk", "au", "ame", "de", "cus", "cn", "kr", "asi", "br",
                              "sp", "fr", "gr", "it", "no", "dk", "nz", "nl", "pl", "ru", "se", "tw", "ca"}
local region_names = {
    ame = "American continent",
    asi = "Asia",
    au = "Australia",
    br = "Brazil",
    ca = "Canada",
    cn = "China",
    cus = "Custom",
    de = "Germany",
    dk = "Denmark",
    eu = "Europe",
    fr = "France",
    gr = "Greece",
    it = "Italy",
    jp = "Japan",
    kr = "Korea",
    nl = "Netherlands",
    no = "Norway",
    nz = "New Zealand",
    pl = "Poland",
    ru = "Russia",
    se = "Sweden",
    sp = "Spain",
    ss = "ScreenScraper",
    tw = "Taiwan",
    uk = "United Kingdom",
    us = "USA",
    wor = "World"
}

local region_action_ids = {"region_reset", "region_save"}

local function set_region_action_active(id)
    if not region_menu then
        return
    end
    for _, aid in ipairs(region_action_ids) do
        local it = region_menu ^ aid
        if it then
            it.active = (aid == id)
        end
    end

    -- Only show one focus indicator at a time. If an action is focused, clear
    -- the region list's active indicator.
    if id and region_list then
        for _, it in ipairs(region_list.children or {}) do
            it.active = false
        end
    end
end

local function accent_status_text()
    if accent_mode == "off" then
        return "Off"
    end
    if accent_mode == "custom" then
        return "Custom #" .. tostring(custom_accent or "")
    end
    return "muOS"
end

-- Preset accent colors (alternatives to muOS default)
local accent_presets = {{
    name = "Blue",
    hex = "3498db"
}, {
    name = "Green",
    hex = "27ae60"
}, {
    name = "Purple",
    hex = "9b59b6"
}, {
    name = "Red",
    hex = "e74c3c"
}}

local function get_active_accent_hex()
    if accent_mode == "off" then
        return nil
    end
    if accent_mode == "custom" then
        return custom_accent
    end
    return "cbaa0f" -- muOS default
end

local function sanitize_hex(s)
    local raw = tostring(s or "")
    raw = raw:gsub("#", ""):gsub("%s+", "")
    raw = raw:lower()
    return raw
end

local function is_hex6(s)
    return type(s) == "string" and #s == 6 and s:match("^[0-9a-f]+$") ~= nil
end

local function sync_accent_to_config()
    if not user_config then
        return
    end
    user_config:insert("main", "accentMode", accent_mode)
    user_config:insert("main", "customAccent", custom_accent)
    user_config:insert("main", "muosAccent", (accent_mode ~= "off") and "1" or "0")
    user_config:insert("main", "accentSource", (accent_mode == "custom") and "custom" or "muos")
    user_config:save()
end

local function apply_theme_now()
    local theme_name = theme_opts[theme_index] or "dark"
    local muos_on = accent_mode ~= "off"
    configs.reload_theme(theme_name, muos_on)
    theme = configs.theme

    if accent_popup then
        accent_popup.visible = false
    end
    if region_popup then
        region_popup.visible = false
    end
    if vk and vk.visible then
        vk.visible = false
        _G.ui_overlay_active = false
    end
    vk = nil

    tools:load()
end

local function update_accent_menu_text()
    if not menu then
        return
    end
    local item = menu ^ "accent_settings"
    if item then
        item.text = "Accent (current: " .. accent_status_text() .. ")"
    end
end

local function update_accent_popup_text()
    if not accent_menu then
        return
    end
    local it_mode = accent_menu ^ "accent_mode"
    if it_mode then
        local label = (accent_mode == "off") and "Off" or ((accent_mode == "custom") and "Custom" or "muOS")
        it_mode.text = "Mode (current: " .. label .. ")"
    end
    local it_edit = accent_menu ^ "accent_custom"
    if it_edit then
        it_edit.disabled = accent_mode ~= "custom"
        it_edit.text = "Custom accent (current: #" .. tostring(custom_accent or "") .. ")"
    end
end

local function cycle_accent_mode()
    if accent_mode == "off" then
        accent_mode = "muos"
    elseif accent_mode == "muos" then
        accent_mode = "custom"
    else
        accent_mode = "off"
    end
    update_accent_popup_text()
    update_accent_menu_text()
end

local function on_edit_custom_accent()
    if not user_config then
        return
    end
    if not vk then
        vk = virtual_keyboard.create({
            title = "Custom Accent",
            placeholder = "RRGGBB",
            on_done = function(text)
                local hex = sanitize_hex(text)
                if not is_hex6(hex) then
                    dispatch_info("Invalid color", "Enter a 6-digit hex color like c29f0c")
                    return
                end
                custom_accent = hex
                sync_accent_to_config()
                update_accent_popup_text()
                update_accent_menu_text()
                if accent_popup then
                    accent_popup.visible = false
                end
                apply_theme_now()
                dispatch_info("Accent", "Changes saved.")
            end,
            on_cancel = function()
            end
        })
    end
    vk:show(custom_accent or "", "custom_accent")
end

local function close_accent_popup()
    if accent_popup and accent_popup.visible then
        accent_popup.visible = false
        sync_accent_to_config()
        update_accent_menu_text()
        apply_theme_now()
        dispatch_info("Accent", "Changes saved.")
    end
end

local function open_accent_settings()
    if not menu or not user_config then
        return
    end
    local item_width = math.min(w_width - 120, 560)

    -- Helper to apply a preset color
    local function apply_preset(hex)
        custom_accent = hex
        accent_mode = "custom"
        sync_accent_to_config()
        update_accent_popup_text()
        update_accent_menu_text()
        if accent_popup then
            accent_popup.visible = false
        end
        apply_theme_now()
        dispatch_info("Accent", "Changes saved.")
    end

    accent_menu = component:root{
        column = true,
        gap = 8,
        width = item_width
    }

    -- Color swatch display component (shows current accent color)
    local swatch_component = component {
        id = "color_swatch",
        width = item_width,
        height = 40,
        draw = function(self)
            local active_hex = get_active_accent_hex()
            local swatch_size = 28
            local padding = 10

            -- Draw background
            love.graphics.setColor(theme:read_color("button", "BUTTON_BACKGROUND", "#2d3436"))
            love.graphics.rectangle("fill", self.x, self.y, self.width, self.height, 6, 6)

            -- Draw color swatch
            if active_hex then
                local r = tonumber(active_hex:sub(1, 2), 16) / 255
                local g = tonumber(active_hex:sub(3, 4), 16) / 255
                local b = tonumber(active_hex:sub(5, 6), 16) / 255
                love.graphics.setColor(r, g, b, 1)
                love.graphics.rectangle("fill", self.x + padding, self.y + 6, swatch_size, swatch_size, 4, 4)
                -- Border
                love.graphics.setColor(1, 1, 1, 0.5)
                love.graphics.rectangle("line", self.x + padding, self.y + 6, swatch_size, swatch_size, 4, 4)
            else
                -- No accent (off mode)
                love.graphics.setColor(0.3, 0.3, 0.3, 1)
                love.graphics.rectangle("fill", self.x + padding, self.y + 6, swatch_size, swatch_size, 4, 4)
                love.graphics.setColor(1, 1, 1, 0.3)
                love.graphics.line(self.x + padding, self.y + 6, self.x + padding + swatch_size,
                    self.y + 6 + swatch_size)
            end

            -- Draw label - show "muOS accent" for muOS mode, hex for custom
            love.graphics.setColor(theme:read_color("label", "LABEL_TEXT", "#dfe6e9"))
            local label_text
            if accent_mode == "off" then
                label_text = "Accent: Off"
            elseif accent_mode == "muos" then
                label_text = "Current: muOS accent"
            else
                label_text = "Current: #" .. (custom_accent or "cbaa0f")
            end
            love.graphics.print(label_text, self.x + padding + swatch_size + 12, self.y + 12)
        end
    }

    accent_menu = accent_menu + swatch_component

    -- Mode toggle
    accent_menu = accent_menu + listitem {
        id = "accent_mode",
        text = "Mode: " .. ((accent_mode == "off") and "Off" or ((accent_mode == "custom") and "Custom" or "muOS")),
        width = item_width,
        onClick = cycle_accent_mode,
        icon = "mode"
    }

    -- Presets header
    accent_menu = accent_menu + listitem {
        id = "accent_presets",
        text = "Presets",
        width = item_width,
        focusable = false,
        disabled = true,
        icon = "presets"
    }

    -- Preset color buttons (using indicator style like region priorities)
    for i, preset in ipairs(accent_presets) do
        local is_active = (accent_mode == "custom" and custom_accent == preset.hex)
        accent_menu = accent_menu + listitem {
            id = "preset_" .. i,
            text = preset.name,
            width = item_width,
            onClick = function()
                apply_preset(preset.hex)
            end
        }
    end

    -- Custom color editor
    accent_menu = accent_menu + listitem {
        id = "accent_custom",
        text = "Custom accent (current: #" .. tostring(custom_accent or "cbaa0f") .. ")",
        width = item_width,
        onClick = on_edit_custom_accent,
        icon = "custom"
    }

    -- Close button
    accent_menu = accent_menu + listitem {
        id = "accent_close",
        text = "Close",
        width = item_width,
        onClick = close_accent_popup,
        icon = "refresh"
    }

    accent_menu:updatePosition(0, 0)
    accent_menu:focusFirstElement()
    accent_popup = popup {
        visible = true,
        title = "Accent Settings",
        id = "accent_popup"
    }
    accent_popup.children = {accent_menu}
    update_accent_popup_text()
end

user_config, skyscraper_config = configs.user_config, configs.skyscraper_config
local finished_tasks = 0
local command_output = ""

dispatch_info = function(title, content)
    if title then
        info_window.title = title
    end
    if content then
        local scraping_log = info_window ^ "scraping_log"
        scraping_log.text = scraping_log.text .. "\n" .. content
    end
    info_window.visible = true
    info_window.fade = 0 -- Reset for zoom animation
end

local function update_state()
    local t = channels.SKYSCRAPER_OUTPUT:pop()
    if t then
        if t.log and string.match(t.log, "%[gen%] Finished \"fake%-rom\"") then
            local f = io.open("/tmp/scrappy_preview_done.txt", "w")
            if f then
                f:write(tostring(os.time()))
                f:close()
            end
        end
        if t.data and next(t.data) then
            dispatch_info(string.format("Updating cache for %s, please wait...", t.data.platform))
        end
        if t.success ~= nil and t.title then
            if t.title ~= "fake-rom" and t.original_filename ~= "fake-rom" then
                finished_tasks = finished_tasks + 1
                dispatch_info(nil, string.format("Finished game: %s", t.title))
                if t.success then
                    artwork.copy_to_catalogue(t.platform, t.title)
                end
            end
        end
        if t.command_finished then
            dispatch_info("Updated cache", "Cache has been updated.")
            finished_tasks = 0
            log.write("Cache updated successfully")
            artwork.process_cached_data()
        end
    end
end

local function update_task_state()
    local t = channels.TASK_OUTPUT:pop()
    if t then
        if t.error and t.error ~= "" and not string.match(t.error or "", "fake%-rom") then
            dispatch_info("Error", t.error)
        end
        if t.output and t.output ~= "" and not string.match(t.output or "", "fake%-rom") then
            command_output = command_output .. t.output .. "\n"
            local scraping_log = info_window ^ "scraping_log"
            scraping_log.text = command_output
        end
        if t.command_finished then
            if t.command == "backup" then
                dispatch_info("Backed up cache",
                    "Cache has been backed up to SD2/ARCHIVE.\nYou can restore it using the muOS Archive Manager")
                log.write("Cache backed up successfully")
            elseif t.command == "backup_sd1" then
                dispatch_info("Backed up cache",
                    "Cache has been backed up to SD1/ARCHIVE.\nYou can restore it using the muOS Archive Manager")
                log.write("Cache backed up successfully to SD1")
            elseif t.command == "migrate" then
                dispatch_info("Migrated cache", "Cache has been migrated to SD2.")
                skyscraper_config:insert("main", "cacheFolder", "\"/mnt/sdcard/scrappy_cache/\"")
                skyscraper_config:save()
                log.write("Cache migrated successfully")
            elseif t.command == "update_app" then
                dispatch_info("Updated Scrappy")
            end
        end
    end
end

local function on_refresh_press()
    user_config:load_platforms()
    user_config:save()
    dispatch_info("Refreshed platforms", "Platforms have been refreshed. \nPlease return to Settings to select them.")
end

local function on_update_press()
    log.write("Updating cache")
    local platforms = user_config:get().platforms
    local rom_path, _ = user_config:get_paths()

    dispatch_info("Updating cache", "Updating cache, please wait...")

    for src, dest in utils.orderedPairs(platforms or {}) do
        if dest ~= "unmapped" then
            local platform_path = string.format("%s/%s", rom_path, src)
            skyscraper.fetch_artwork(platform_path, src, dest)
        end
    end
end

local function on_import_press()
    log.write("Importing custom data")
    dispatch_info("Importing custom data", "Running import command...")
    local import_path = WORK_DIR .. "/static/.skyscraper/import"
    local lookup_folders = {}

    for _, item in ipairs(nativefs.getDirectoryItems(import_path) or {}) do
        local file_info = nativefs.getInfo(string.format("%s/%s", import_path, item))
        if file_info and file_info.type == "directory" then
            table.insert(lookup_folders, item)
        end
    end

    if #lookup_folders == 0 then
        log.write("Import Error: No folders to import")
        dispatch_info("Error", "Error: no folders to import.")
        return
    end

    local platforms = user_config:get().platforms
    local rom_path, _ = user_config:get_paths()

    local any_match = false

    for _, folder in ipairs(lookup_folders) do
        for src, dest in utils.orderedPairs(platforms or {}) do
            if folder == dest then
                any_match = true
                local platform_path = string.format("%s/%s", rom_path, src)
                skyscraper.custom_import(platform_path, dest)
            end
        end
    end

    if not any_match then
        log.write("No matching platforms found")
        dispatch_info("Error", "Error: No matching platforms found.")
        return
    end
end

local function on_change_scraper()
    local index = scraper_index + 1
    if index > #scraper_opts then
        index = 1
    end
    local item = menu ^ "scraper_module"

    skyscraper.module = scraper_opts[index]
    scraper_index = index
    item.text = "Change Skyscraper module (current: " .. scraper_opts[scraper_index] .. ")"

    -- Persist the selection to config
    user_config:insert("main", "scraperModule", scraper_opts[index])
    user_config:save()
end

local function on_change_theme()
    local index = theme_index + 1
    if index > #theme_opts then
        index = 1
    end
    local item = menu ^ "theme_toggle"

    theme_index = index
    item.text = "Change theme (current: " .. theme_opts[theme_index] .. ")"

    -- Persist the selection to config
    user_config:insert("main", "theme", theme_opts[index])
    user_config:save()

    apply_theme_now()
    dispatch_info("Theme Changed", "Theme applied.")
end

local function on_open_accent_settings()
    open_accent_settings()
end

local function on_toggle_offline_mode()
    if offline_mode then
        -- Already ON, disable directly
        offline_mode = false
        local item = menu ^ "offline_toggle"
        if item then
            item.text = "Offline Mode: OFF"
        end
        user_config:insert("main", "offlineMode", "0")
        user_config:save()
        dispatch_info("Offline Mode",
            "Offline mode has been disabled. \nPlease restart the application for the changes to take effect.")
    else
        -- Show confirmation popup before enabling
        offline_popup_visible = true
        offline_fade = 0
    end
end

local function on_confirm_offline_mode()
    offline_popup_visible = false
    offline_mode = true
    local item = menu ^ "offline_toggle"
    if item then
        item.text = "Offline Mode: ON"
    end
    user_config:insert("main", "offlineMode", "1")
    user_config:save()
    dispatch_info("Offline Mode",
        "Offline mode has been enabled. \nPlease restart the application for the changes to take effect.")
end

local function on_cancel_offline_mode()
    offline_popup_visible = false
end

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function parse_region_prios(str)
    local raw = utils.strip_quotes(str or "")
    local list = {}
    for part in tostring(raw):gmatch("[^,]+") do
        local p = trim(part)
        if p ~= "" then
            table.insert(list, p)
        end
    end
    if #list == 0 then
        for _, k in ipairs(default_region_prios) do
            table.insert(list, k)
        end
    end
    return list
end

local function rebuild_region_list(focus_index)
    if not region_list then
        return
    end
    region_list.children = {}
    region_list.height = 0

    for i, key in ipairs(region_prios) do
        local name = region_names[key] or ""
        local label = name ~= "" and (key .. " - " .. name) or key
        region_list = region_list + listitem {
            id = "region_" .. tostring(i),
            text = string.format("%02d. %s", i, label),
            width = region_list.width,
            onFocus = function()
                selected_region_index = i
                for _, it in ipairs(region_list.children) do
                    it.active = (it.id == ("region_" .. tostring(i)))
                end

                -- Only show one focus indicator at a time. If a region is focused,
                -- clear action highlights.
                set_region_action_active(nil)
            end,
            active = (i == selected_region_index),
            indicator = 1
        }
    end

    local idx = focus_index or selected_region_index
    idx = math.max(1, math.min(#region_list.children, idx))
    selected_region_index = idx
    local focus_item = region_list % ("region_" .. tostring(idx))
    if focus_item and region_menu then
        region_menu:setFocus(focus_item)
    elseif region_menu then
        region_menu:focusFirstElement()
    end
end

local function move_region(delta)
    if #region_prios < 2 then
        return
    end
    local i = math.max(1, math.min(#region_prios, selected_region_index))
    local j = i + delta
    if j < 1 or j > #region_prios then
        return
    end
    region_prios[i], region_prios[j] = region_prios[j], region_prios[i]
    selected_region_index = j
    rebuild_region_list(selected_region_index)
end

local function reset_region_prios()
    region_prios = {}
    for _, k in ipairs(default_region_prios) do
        table.insert(region_prios, k)
    end
    selected_region_index = 1
    rebuild_region_list(1)
end

-- Recursively delete all contents of a directory
local function clear_directory(path)
    local items = nativefs.getDirectoryItems(path)
    if not items then
        return
    end
    for _, item in ipairs(items) do
        local full_path = path .. "/" .. item
        local info = nativefs.getInfo(full_path)
        if info then
            if info.type == "directory" then
                clear_directory(full_path)
                nativefs.remove(full_path)
            else
                nativefs.remove(full_path)
            end
        end
    end
end

-- Get the cache folder path from config
local function get_cache_path()
    local cache_path = skyscraper_config:read("main", "cacheFolder")
    cache_path = utils.strip_quotes(cache_path or "")
    if cache_path == "" then
        cache_path = WORK_DIR .. "/data/cache"
    end
    return cache_path
end

-- Clear all potential cache locations (SD1 and SD2)
local function clear_all_caches()
    -- 1. Clear the default SD1 cache
    local sd1_cache = WORK_DIR .. "/data/cache"
    log.write("Clearing SD1 cache: " .. sd1_cache)
    clear_directory(sd1_cache)

    -- 2. Clear the SD2 cache (standard location)
    local sd2_cache = "/mnt/sdcard/scrappy_cache"
    log.write("Clearing SD2 cache: " .. sd2_cache)
    clear_directory(sd2_cache)

    -- 3. Clear the currently configured cache folder if it's different (e.g. if pointing elsewhere)
    local config_cache = skyscraper_config:read("main", "cacheFolder")
    config_cache = utils.strip_quotes(config_cache or "")
    if config_cache ~= "" and config_cache ~= sd2_cache then
        log.write("Clearing custom configured cache: " .. config_cache)
        clear_directory(config_cache)
    end
end

-- Called when user confirms cache deletion
local function on_confirm_cache_clear()
    -- Clear all potential caches
    clear_all_caches()

    -- Save the pending region priorities
    if pending_region_prios then
        local joined = table.concat(pending_region_prios, ", ")
        skyscraper_config:insert("main", "regionPrios", string.format('"%s"', joined))
        skyscraper_config:save()
        log.write("Region priorities saved")
    end

    -- Close popups
    confirm_popup_visible = false
    pending_region_prios = nil
    if region_popup then
        region_popup.visible = false
    end
    dispatch_info("Region Priorities Saved", "Cache has been cleared and region priorities updated.")
end

-- Called when user cancels cache deletion
local function on_cancel_cache_clear()
    confirm_popup_visible = false
    pending_region_prios = nil
end

-- Show the cache warning confirmation popup
local function show_cache_warning()
    confirm_popup_visible = true
    confirm_fade = 0
end

-- Standalone clear cache functions
local function on_confirm_clear_cache_standalone()
    clear_all_caches()
    clear_cache_popup_visible = false
    dispatch_info("Cache Cleared", "Skyscraper cache has been cleared.\nYou will need to re-scrape your ROMs.")
end

local function on_cancel_clear_cache_standalone()
    clear_cache_popup_visible = false
end

local function on_clear_cache_press()
    clear_cache_popup_visible = true
    clear_cache_fade = 0
end

local function save_region_prios()
    -- Store pending changes and show confirmation
    pending_region_prios = {}
    for i, v in ipairs(region_prios) do
        pending_region_prios[i] = v
    end
    show_cache_warning()
end

local function open_region_editor()
    region_prios = parse_region_prios(skyscraper_config:read("main", "regionPrios"))
    selected_region_index = 1

    region_menu = component:root{
        column = true,
        gap = 10
    }
    local item_width = math.min(w_width - 120, 560)
    local list_height = math.min(w_height - 220, 360)

    region_list = component {
        id = "region_list",
        column = true,
        gap = 0,
        width = item_width,
        height = 0
    }
    rebuild_region_list(1)

    region_menu = region_menu + (component {
        row = true,
        gap = 6
    } + icon {
        name = "dpad",
        size = 24,
        y = 6
    } + label {
        text = "Navigate •",
        y = 6
    } + icon {
        name = "dpad_horizontal",
        size = 24,
        y = 6
    } + label {
        text = "Reorder •",
        y = 6
    } + icon {
        name = "button_a",
        size = 24,
        y = 8
    } + label {
        text = "Confirm",
        y = 6
    }) + (scroll_container {
        width = item_width,
        height = list_height,
        scroll_speed = 30
    } + region_list) + listitem {
        id = "region_reset",
        text = "Reset to default",
        width = item_width,
        onClick = reset_region_prios,
        onFocus = function()
            set_region_action_active("region_reset")
        end,
        icon = "refresh"
    } + listitem {
        id = "region_save",
        text = "Save",
        width = item_width,
        onClick = save_region_prios,
        onFocus = function()
            set_region_action_active("region_save")
        end,
        icon = "save"
    }

    region_menu:updatePosition(0, 0)
    region_menu:focusFirstElement()

    region_popup = popup {
        visible = true,
        title = "Region Priorities",
        id = "region_popup"
    }
    region_popup.children = {region_menu}
end

local function on_reset_configs()
    user_config:start_fresh()
    skyscraper_config:start_fresh()
    dispatch_info("Configs reset", "Configs have been reset.")
end

local function on_backup_cache()
    log.write("Backing up cache to ARCHIVE folder")
    dispatch_info("Backing up cache to SD2/ARCHIVE folder", "Please wait...")
    local thread = love.thread.newThread("lib/backend/task_backend.lua")
    thread:start("backup")
end

local function on_backup_cache_sd1()
    log.write("Backing up cache to SD1/ARCHIVE folder")
    dispatch_info("Backing up cache to SD1/ARCHIVE folder", "Please wait...")
    local thread = love.thread.newThread("lib/backend/task_backend.lua")
    thread:start("backup_sd1")
end

local function on_migrate_cache()
    log.write("Migrating cache to SD2")
    dispatch_info("Migrating cache to SD2", "Please wait...")
    local thread = love.thread.newThread("lib/backend/task_backend.lua")
    thread:start("migrate")
end

local function on_toggle_artwork_manager()
    if artwork_manager_running then
        os.execute("pkill -9 -f artwork_manager.py")
        artwork_manager_running = false
        artwork_manager_status = "Server stopped."
        return
    end

    local ip = utils.get_ip_address()
    if ip then
        local server_path = WORK_DIR .. "/scripts/artwork_manager.py"
        local logo_path = WORK_DIR .. "/assets/scrappy_logo.png"
        local theme_name = theme:get_current_name() or "dark"
        local accent_color = user_config:read("main", "customAccent") or "cbaa0f"
        local accent_mode = tostring(user_config:read("main", "accentMode") or "muos"):lower()
        if accent_mode == "muos" then
            accent_color = theme:read("button", "BUTTON_FOCUS") or "cbaa0f"
        end
        local cache_path = get_cache_path()
        
        os.execute(string.format('python3 "%s" --theme %s --accent "%s" --logo "%s" --cache "%s" > /dev/null 2>&1 &',
            server_path, theme_name, accent_color, logo_path, cache_path))

        artwork_manager_running = true
        artwork_manager_ip = ip
        artwork_manager_status = 'Go to http://' .. ip .. ':8082 on phone/PC (same WiFi)'
        regen_check_timer = 0
    else
        artwork_manager_status = "No IP found! Connect to WiFi."
    end
end

local function on_toggle_template_maker()
    if template_maker_running then
        os.execute("pkill -9 -f template_maker.py")
        template_maker_running = false
        template_maker_status = "Server stopped."
        return
    end

    local ip = utils.get_ip_address()
    if ip then
        local server_path = WORK_DIR .. "/scripts/template_maker.py"
        local logo_path = WORK_DIR .. "/assets/scrappy_logo.png"
        local theme_name = theme:get_current_name() or "dark"
        local accent_color = user_config:read("main", "customAccent") or "cbaa0f"
        local accent_mode = tostring(user_config:read("main", "accentMode") or "muos"):lower()
        if accent_mode == "muos" then
            accent_color = theme:read("button", "BUTTON_FOCUS") or "cbaa0f"
        end
        local templates_dir = WORK_DIR .. "/templates"
        local resources_dir = WORK_DIR .. "/templates/resources"
        local sample_dir = WORK_DIR .. "/sample"

        os.execute(string.format(
            'python3 "%s" --theme %s --accent "%s" --logo "%s" --templates-dir "%s" --resources-dir "%s" --sample-dir "%s" > /dev/null 2>&1 &',
            server_path, theme_name, accent_color, logo_path,
            templates_dir, resources_dir, sample_dir))

        template_maker_running = true
        template_maker_ip = ip
        template_maker_status = 'Go to http://' .. ip .. ':8083 on phone/PC (same WiFi)'
        tpl_regen_check_timer = 0
    else
        template_maker_status = "No IP found! Connect to WiFi."
    end
end

local function on_app_update()
    log.write("Updating Scrappy")
    dispatch_info("Updating Scrappy", "Please wait...")
    local thread = love.thread.newThread("lib/backend/task_backend.lua")
    thread:start("update_app")
end

function tools:load()
    -- Restore saved scraper module from config
    local saved_scraper = user_config:read("main", "scraperModule")
    if saved_scraper then
        for i, opt in ipairs(scraper_opts) do
            if opt == saved_scraper then
                scraper_index = i
                skyscraper.module = saved_scraper
                break
            end
        end
    end

    -- Restore saved theme from config
    local saved_theme = user_config:read("main", "theme")
    if saved_theme then
        for i, opt in ipairs(theme_opts) do
            if opt == saved_theme then
                theme_index = i
                break
            end
        end
    end

    local saved_custom = sanitize_hex(user_config:read("main", "customAccent") or "cbaa0f")
    if is_hex6(saved_custom) then
        custom_accent = saved_custom
    else
        custom_accent = "cbaa0f"
    end

    local saved_mode = user_config:read("main", "accentMode")
    if saved_mode then
        saved_mode = tostring(saved_mode):lower()
        if saved_mode ~= "off" and saved_mode ~= "muos" and saved_mode ~= "custom" then
            saved_mode = "muos"
        end
        accent_mode = saved_mode
    else
        local saved_muos = user_config:read("main", "muosAccent")
        local muos_on = (saved_muos == nil) or (saved_muos ~= "0")
        if not muos_on then
            accent_mode = "off"
        else
            local src = tostring(user_config:read("main", "accentSource") or "muos"):lower()
            accent_mode = (src == "custom") and "custom" or "muos"
        end
    end

    muos_accent = accent_mode ~= "off"

    -- Restore offline mode setting from config
    local saved_offline = user_config:read("main", "offlineMode")
    offline_mode = (saved_offline == "1")

    menu = component:root{
        column = true,
        gap = 10
    }
    info_window = popup {
        visible = false
    }
    local item_width = w_width - 20

    menu = menu + (scroll_container {
        width = w_width,
        height = w_height - 60, -- Reduced to prevent footer overlap (was -20)
        scroll_speed = 30
    } + (component {
        column = true,
        gap = 10
    } -- TODO: Implement auto update
    + listitem {
        text = "Update Scrappy",
        width = item_width,
        onClick = on_app_update,
        icon = "download"
    } + listitem {
        text = "Migrate cache to SD2",
        width = item_width,
        onClick = on_migrate_cache,
        icon = "sd_card"
    } + listitem {
        text = "Backup cache to SD1/ARCHIVE folder",
        width = item_width,
        onClick = on_backup_cache_sd1,
        icon = "backup"
    } + listitem {
        text = "Backup cache to SD2/ARCHIVE folder",
        width = item_width,
        onClick = on_backup_cache,
        icon = "backup"
    } + listitem {
        id = "scraper_module",
        text = "Change Skyscraper module (current: " .. scraper_opts[scraper_index] .. ")",
        width = item_width,
        onClick = on_change_scraper,
        icon = "canvas"
    } + listitem {
        id = "theme_toggle",
        text = "Change theme (current: " .. theme_opts[theme_index] .. ")",
        width = item_width,
        onClick = on_change_theme,
        icon = "theme"
    } + listitem {
        id = "accent_settings",
        text = "Accent (current: " .. accent_status_text() .. ")",
        width = item_width,
        onClick = on_open_accent_settings,
        icon = "accent"
    } + listitem {
        id = "offline_toggle",
        text = "Offline Mode: " .. (offline_mode and "ON" or "OFF"),
        width = item_width,
        onClick = on_toggle_offline_mode,
        icon = "offline"
    } + listitem {
        id = "clock_toggle",
        text = "Show Clock: " .. (user_config:read("main", "clockEnabled") == "1" and "ON" or "OFF"),
        width = item_width,
        icon = "clock",
        onClick = function()
            local current = user_config:read("main", "clockEnabled") or "1"
            local new_val = (current == "1") and "0" or "1"
            user_config:insert("main", "clockEnabled", new_val)
            user_config:save()
            local item = menu ^ "clock_toggle"
            if item then
                item.text = "Show Clock: " .. (new_val == "1" and "ON" or "OFF")
                -- icon remains "clock"
            end
        end
    } + listitem {
        id = "clock_format",
        text = "Time Format: " .. (user_config:read("main", "clockFormat") or "12h"),
        width = item_width,
        icon = "time",
        onClick = function()
            local current = user_config:read("main", "clockFormat") or "12h"
            local new_val = (current == "12h") and "24h" or "12h"
            user_config:insert("main", "clockFormat", new_val)
            user_config:save()
            local item = menu ^ "clock_format"
            if item then
                item.text = "Time Format: " .. new_val
            end
        end
    } + listitem {
        text = "Edit region priorities",
        width = item_width,
        onClick = open_region_editor,
        icon = "region"
    } + listitem {
        text = "Update cache (uses threads, doesn't generate artwork)",
        width = item_width,
        onClick = on_update_press,
        icon = "cache"
    } + listitem {
        text = "Run custom import (adds custom data to cache, read Wiki!)",
        width = item_width,
        onClick = on_import_press,
        icon = "file_import"
    } + listitem {
        text = "Rescan ROMs folders (overwrites [platforms] config)",
        width = item_width,
        onClick = on_refresh_press,
        icon = "folder"
    } + listitem {
        text = "Reset configs (can't be undone!)",
        width = item_width,
        onClick = on_reset_configs,
        icon = "refresh"
    } + listitem {
        text = "Clear Skyscraper cache (can't be undone!)",
        width = item_width,
        onClick = on_clear_cache_press,
        icon = "cache_clean"
    } + listitem {
        id = "artwork_manager_toggle",
        text = function()
            if artwork_manager_running then
                return "Stop Artwork Manager (http://" .. (artwork_manager_ip or "") .. ":8082)"
            elseif artwork_manager_status == "No IP found! Connect to WiFi." then
                return "Artwork Manager (No WiFi Connection!)"
            else
                return "Start Artwork Manager (Web)"
            end
        end,
        width = item_width,
        onClick = on_toggle_artwork_manager,
        icon = "artwork"
    } + listitem {
        id = "template_maker_toggle",
        text = function()
            if template_maker_running then
                return "Stop Template Maker (http://" .. (template_maker_ip or "") .. ":8083)"
            elseif template_maker_status == "No IP found! Connect to WiFi." then
                return "Template Maker (No WiFi Connection!)"
            else
                return "Start Template Maker (Web)"
            end
        end,
        width = item_width,
        onClick = on_toggle_template_maker,
        icon = "canvas"
    }))

    info_window = info_window + (component {
        column = true,
        gap = 15
    } + output_log {
        visible = false,
        id = "scraping_log",
        width = info_window.width - 20,
        height = w_height * 0.50
    })

    menu:updatePosition(10, 10)
    menu:focusFirstElement()
    -- Create help footer
    footer = component { row = true, gap = 40 }
        + label { text = "Select", icon = "button_a" }
        + label { text = "Back", icon = "button_b" }
        + label { text = "Navigate", icon = "dpad" }
    footer:updatePosition(w_width * 0.5 - footer.width * 0.5 - 20, w_height - footer.height - 10)
end

function tools:update(dt)
    if vk and vk.visible then
        vk:update(dt)
    end
    if region_popup and region_popup.visible and region_menu then
        region_menu:update(dt)
    elseif accent_popup and accent_popup.visible and accent_menu then
        accent_menu:update(dt)
    else
        menu:update(dt)
    end
    -- Update info window components (enables marquee scrolling in log)
    if info_window and info_window.visible then
        info_window:update(dt)
    end
    update_state()
    update_task_state()

    -- Monitor regeneration requests from web UI
    if artwork_manager_running then
        regen_check_timer = regen_check_timer + dt
        if regen_check_timer >= 1.0 then
            regen_check_timer = 0
            local f = io.open(REGEN_FILE, "r")
            if f then
                local content = f:read("*a")
                f:close()
                os.remove(REGEN_FILE)
                
                local data = json.decode(content)
                if data and data.platform and data.rom then
                    local rom_path, _ = user_config:get_paths()
                    local platforms = user_config:get().platforms
                    
                    -- Find the actual source folder for this platform mapping
                    local input_folder = data.platform
                    for src, dest in pairs(platforms or {}) do
                        if dest == data.platform then
                            input_folder = src
                            break
                        end
                    end
                    
                    local platform_path = rom_path .. "/" .. input_folder
                    local xml = data.xml or "box2d"
                    -- Trigger regeneration with refresh and specified template
                    skyscraper.update_artwork(platform_path, data.rom, input_folder, data.platform, xml) 
                end
            end
        end
    end

    -- Monitor template maker preview requests
    if template_maker_running then
        tpl_regen_check_timer = tpl_regen_check_timer + dt
        if tpl_regen_check_timer >= 1.0 then
            tpl_regen_check_timer = 0
            local f = io.open(TPL_REGEN_FILE, "r")
            if f then
                local content = f:read("*a")
                f:close()
                os.remove(TPL_REGEN_FILE)

                local data = json.decode(content)
                if data and data.xml_path then
                    skyscraper.update_sample(data.xml_path)
                end
            end
        end
    end
end

-- Load button icons
local button_a_icon = love.graphics.newImage("assets/inputs/switch_button_a.png")
local button_b_icon = love.graphics.newImage("assets/inputs/switch_button_b.png")

-- Draw the confirmation popup
local function draw_confirm_popup()
    if not confirm_popup_visible then
        confirm_fade = 0
        return
    end

    confirm_fade = confirm_fade + (1 - confirm_fade) * 15 * love.timer.getDelta()
    if confirm_fade > 0.999 then confirm_fade = 1 end

    local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
    local font = love.graphics.getFont()
    local font_h = font:getHeight()

    love.graphics.push()
    love.graphics.origin()

    -- Dim background
    love.graphics.setColor(0, 0, 0, 0.8 * confirm_fade)
    love.graphics.rectangle("fill", 0, 0, sw, sh)

    local popup_scale = 0.9 + 0.1 * confirm_fade
    love.graphics.translate(sw / 2, sh / 2)
    love.graphics.scale(popup_scale, popup_scale)
    love.graphics.translate(-sw / 2, -sh / 2)

    -- Popup box dimensions
    local box_w = math.min(sw - 40, 340)
    local box_h = 140
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
    love.graphics.printf("Clear Cache?", box_x, box_y + 12, box_w, "center")

    -- Warning message
    local msg = "Changing region priorities will delete cached artwork."
    love.graphics.printf(msg, box_x + 15, box_y + 35, box_w - 30, "center")

    -- Button icons and labels
    local icon_size = 24
    local btn_y = box_y + box_h - 38
    local left_center = box_x + box_w * 0.25
    local right_center = box_x + box_w * 0.75

    local proceed_total_w = icon_size + 6 + font:getWidth("Proceed")
    local proceed_x = left_center - proceed_total_w / 2
    if button_a_icon then
        local iw, ih = button_a_icon:getDimensions()
        local sx, sy = icon_size / iw, icon_size / ih
        love.graphics.draw(button_a_icon, proceed_x, btn_y, 0, sx, sy)
    end
    love.graphics.print("Proceed", proceed_x + icon_size + 6, btn_y + (icon_size - font_h) / 2)

    local cancel_total_w = icon_size + 6 + font:getWidth("Cancel")
    local cancel_x = right_center - cancel_total_w / 2
    if button_b_icon then
        local iw, ih = button_b_icon:getDimensions()
        local sx, sy = icon_size / iw, icon_size / ih
        love.graphics.draw(button_b_icon, cancel_x, btn_y, 0, sx, sy)
    end
    love.graphics.print("Cancel", cancel_x + icon_size + 6, btn_y + (icon_size - font_h) / 2)

    love.graphics.pop()
end

-- Draw the standalone clear cache popup
local function draw_clear_cache_popup()
    if not clear_cache_popup_visible then
        clear_cache_fade = 0
        return
    end

    clear_cache_fade = clear_cache_fade + (1 - clear_cache_fade) * 15 * love.timer.getDelta()
    if clear_cache_fade > 0.999 then clear_cache_fade = 1 end

    local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
    local font = love.graphics.getFont()
    local font_h = font:getHeight()

    love.graphics.push()
    love.graphics.origin()

    -- Dim background
    love.graphics.setColor(0, 0, 0, 0.8 * clear_cache_fade)
    love.graphics.rectangle("fill", 0, 0, sw, sh)

    local popup_scale = 0.9 + 0.1 * clear_cache_fade
    love.graphics.translate(sw / 2, sh / 2)
    love.graphics.scale(popup_scale, popup_scale)
    love.graphics.translate(-sw / 2, -sh / 2)

    -- Popup box dimensions - taller for more content
    local box_w = math.min(sw - 40, 380)
    local box_h = 180
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
    love.graphics.printf("Clear Cache?", box_x, box_y + 15, box_w, "center")

    -- Warning message
    local msg = "This clears the cache. Re-scrape ROMs to rebuild.\nExisting artwork will not be deleted."
    love.graphics.printf(msg, box_x + 15, box_y + 45, box_w - 30, "center")

    -- Button icons and labels - positioned below text
    local icon_size = 24
    local btn_y = box_y + box_h - 45

    -- Calculate button positions
    local left_center = box_x + box_w * 0.25
    local right_center = box_x + box_w * 0.75

    -- Clear button (A)
    local proceed_total_w = icon_size + 6 + font:getWidth("Clear")
    local proceed_x = left_center - proceed_total_w / 2
    if button_a_icon then
        local iw, ih = button_a_icon:getDimensions()
        local sx, sy = icon_size / iw, icon_size / ih
        love.graphics.draw(button_a_icon, proceed_x, btn_y, 0, sx, sy)
    end
    love.graphics.print("Clear", proceed_x + icon_size + 6, btn_y + (icon_size - font_h) / 2)

    -- Cancel button (B)
    local cancel_total_w = icon_size + 6 + font:getWidth("Cancel")
    local cancel_x = right_center - cancel_total_w / 2
    if button_b_icon then
        local iw, ih = button_b_icon:getDimensions()
        local sx, sy = icon_size / iw, icon_size / ih
        love.graphics.draw(button_b_icon, cancel_x, btn_y, 0, sx, sy)
    end
    love.graphics.print("Cancel", cancel_x + icon_size + 6, btn_y + (icon_size - font_h) / 2)

    love.graphics.pop()
end


-- Draw the offline mode confirmation popup
local function draw_offline_popup()
    if not offline_popup_visible then
        offline_fade = 0
        return
    end

    offline_fade = offline_fade + (1 - offline_fade) * 15 * love.timer.getDelta()
    if offline_fade > 0.999 then offline_fade = 1 end

    local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
    local font = love.graphics.getFont()
    local font_h = font:getHeight()

    love.graphics.push()
    love.graphics.origin()

    -- Dim background
    love.graphics.setColor(0, 0, 0, 0.8 * offline_fade)
    love.graphics.rectangle("fill", 0, 0, sw, sh)

    local popup_scale = 0.9 + 0.1 * offline_fade
    love.graphics.translate(sw / 2, sh / 2)
    love.graphics.scale(popup_scale, popup_scale)
    love.graphics.translate(-sw / 2, -sh / 2)

    -- Popup box dimensions - taller for more content
    local box_w = math.min(sw - 40, 420)
    local box_h = 330
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
    love.graphics.printf("Enable Offline Mode?", box_x, box_y + 15, box_w, "center")

    -- Explanation message
    local msg = "Offline Mode allows scraping using cached data without internet.\n\n" ..
                    "• Works only with 'Scrape All' (uses cached data)\n" ..
                    "• 'Scrape only missing artwork' requires internet\n" ..
                    "• Single ROM scraping requires internet\n" .. "• WiFi warnings will be suppressed"
    love.graphics.printf(msg, box_x + 15, box_y + 45, box_w - 30, "left")

    -- Button icons and labels
    local icon_size = 24
    local btn_y = box_y + box_h - 45

    -- Calculate button positions
    local left_center = box_x + box_w * 0.25
    local right_center = box_x + box_w * 0.75

    -- Enable button (A)
    local proceed_total_w = icon_size + 6 + font:getWidth("Enable")
    local proceed_x = left_center - proceed_total_w / 2
    if button_a_icon then
        local iw, ih = button_a_icon:getDimensions()
        local sx, sy = icon_size / iw, icon_size / ih
        love.graphics.draw(button_a_icon, proceed_x, btn_y, 0, sx, sy)
    end
    love.graphics.print("Enable", proceed_x + icon_size + 6, btn_y + (icon_size - font_h) / 2)

    -- Cancel button (B)
    local cancel_total_w = icon_size + 6 + font:getWidth("Cancel")
    local cancel_x = right_center - cancel_total_w / 2
    if button_b_icon then
        local iw, ih = button_b_icon:getDimensions()
        local sx, sy = icon_size / iw, icon_size / ih
        love.graphics.draw(button_b_icon, cancel_x, btn_y, 0, sx, sy)
    end
    love.graphics.print("Cancel", cancel_x + icon_size + 6, btn_y + (icon_size - font_h) / 2)

    love.graphics.pop()
end


function tools:draw()
    love.graphics.clear(theme:read_color("main", "BACKGROUND", "#000000"))
    menu:draw()
    info_window:draw()
    if region_popup and region_popup.visible then
        region_popup:draw()
    end
    if accent_popup and accent_popup.visible then
        accent_popup:draw()
    end
    -- Draw confirmation popup on top of everything
    draw_confirm_popup()
    draw_clear_cache_popup()
    draw_offline_popup()

    -- Draw footer (hidden if any popup/VK is visible)
    local popup_active = (region_popup and region_popup.visible) or 
                         (accent_popup and accent_popup.visible) or 
                         confirm_popup_visible or 
                         clear_cache_popup_visible or 
                         offline_popup_visible
    
    if footer and not (vk and vk.visible) and not popup_active and not info_window.visible then
        footer:draw()
    end

    if vk and vk.visible then
        vk:draw()
    end
end

function tools:keypressed(key)
    -- 1. Handle info popup (highest priority)
    if info_window.visible then
        if key == "return" or key == "a" or key == "escape" or key == "b" then
            info_window.visible = false
            command_output = ""
            local scraping_log = info_window ^ "scraping_log"
            if scraping_log then scraping_log.text = "" end
            return
        end
        return -- Block all other keys
    end

    -- 2. Handle modal confirmation popups
    if clear_cache_popup_visible then
        if key == "return" or key == "a" then
            on_confirm_clear_cache_standalone()
            return
        elseif key == "escape" or key == "b" then
            on_cancel_clear_cache_standalone()
            return
        end
        return -- Block all other keys while popup is visible
    end

    if confirm_popup_visible then
        if key == "return" or key == "a" then
            on_confirm_cache_clear()
            return
        elseif key == "escape" or key == "b" then
            on_cancel_cache_clear()
            return
        end
        return -- Block all other keys while confirmation is visible
    end

    if offline_popup_visible then
        if key == "return" or key == "a" then
            on_confirm_offline_mode()
            return
        elseif key == "escape" or key == "b" then
            on_cancel_offline_mode()
            return
        end
        return -- Block all other keys while popup is visible
    end

    -- 3. Accent popup
    if accent_popup and accent_popup.visible then
        if key == "escape" then
            close_accent_popup()
            return
        end
        if accent_menu then
            accent_menu:keypressed(key)
        end
        return
    end

    -- 4. Virtual Keyboard
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



    if region_popup and region_popup.visible then
        if key == "escape" then
            region_popup.visible = false
            return
        end
        if region_menu and (key == "left" or key == "right") then
            local focused = region_menu:getRoot().focusedElement
            if focused and type(focused.id) == "string" and focused.id:match("^region_%d+$") then
                move_region(key == "left" and -1 or 1)
                return
            end
        end
        if region_menu then
            region_menu:keypressed(key)
        end
        return
    end

    menu:keypressed(key)
    if key == "escape" then
        if info_window.visible then
            -- Already handled above
        else
            scenes:pop()
        end
    end
end

function tools:gamepadpressed(joystick, button)
    local btn = type(button) == 'string' and button:lower() or button

    -- Handle info popup first
    -- 1. Handle info popup (highest priority)
    if info_window.visible then
        if btn == "a" or btn == "b" then
            info_window.visible = false
            command_output = ""
            local scraping_log = info_window ^ "scraping_log"
            if scraping_log then scraping_log.text = "" end
            return true
        end
        return true -- Block all buttons
    end

    -- 2. Handle modal confirmation popups
    if clear_cache_popup_visible then
        if btn == "a" then
             on_confirm_clear_cache_standalone()
             return true
        elseif btn == "b" then
             on_cancel_clear_cache_standalone()
             return true
        end
        return true
    end

    if confirm_popup_visible then
        if btn == "a" then
             on_confirm_cache_clear()
             return true
        elseif btn == "b" then
             on_cancel_cache_clear()
             return true
        end
        return true
    end

    if offline_popup_visible then
        if btn == 'a' then
            on_confirm_offline_mode()
            return true
        elseif btn == 'b' then
            on_cancel_offline_mode()
            return true
        end
        return true -- Block all buttons while popup is visible
    end

    -- 3. Handle virtual keyboard input first if visible
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

    -- Handle region popup
    if region_popup and region_popup.visible then
        if btn == "b" then
            region_popup.visible = false
            return true
        elseif btn == "dpup" or btn == "dpdown" then
            if region_menu then
               -- Navigate region list
               local direction = (btn == "dpup") and "up" or "down"
               region_menu:keypressed(direction)
            end
            return true
        elseif btn == "dpleft" or btn == "dpright" then
            if region_menu then
                local focused = region_menu:getRoot().focusedElement
                if focused and type(focused.id) == "string" and focused.id:match("^region_%d+$") then
                    move_region(btn == "dpleft" and -1 or 1)
                    return true
                end
            end
            return true
        end
         -- Handle A/Select/Start if needed for reordering logic
         if region_menu then
            -- simplistic mapping for now
             local map = {a='return'}
             if map[btn] then region_menu:keypressed(map[btn]) end
         end
        return true
    end



    -- Rely on global input handling for D-Pad (to support hold-repeat) and standard keys
    return false
end

return tools
