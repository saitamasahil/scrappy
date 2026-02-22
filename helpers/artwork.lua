local log = require("lib.log")
local metadata = require("lib.metadata")
local config = require("helpers.config")
local utils = require("helpers.utils")
local muos = require("helpers.muos")
local pprint = require("lib.pprint")

local artwork = {
    cached_game_ids = {}
}

local output_types = {
    BOX = "box",
    PREVIEW = "preview",
    SPLASH = "splash"
}

artwork.output_map = {
    [output_types.BOX] = "covers",
    [output_types.PREVIEW] = "screenshots",
    [output_types.SPLASH] = "wheels"
}

local user_config, skyscraper_config = config.user_config, config.skyscraper_config

local function xml_decode(s)
    if not s then return s end
    local entities = {
        amp = "&",
        quot = "\"",
        apos = "'",
        lt = "<",
        gt = ">"
    }
    s = s:gsub("&(%a+);", function(entity)
        return entities[entity] or ("&" .. entity .. ";")
    end)
    s = s:gsub("&#(%d+);", function(n)
        local status, char = pcall(string.char, tonumber(n))
        return status and char or ("&#" .. n .. ";")
    end)
    s = s:gsub("&#x(%x+);", function(h)
        local status, char = pcall(string.char, tonumber(h, 16))
        return status and char or ("&#x" .. h .. ";")
    end)
    return s
end

-- Normalize internal distinctions to Skyscraper/peas output folder keys
local function normalize_platform(platform)
    return utils.normalize_platform(platform)
end

function artwork.get_artwork_path()
    local artwork_xml = skyscraper_config:read("main", "artworkXml")
    if not artwork_xml or artwork_xml == "\"\"" then
        return nil
    end
    artwork_xml = artwork_xml:gsub('"', '')
    return artwork_xml
end

function artwork.get_artwork_name()
    local artwork_path = artwork.get_artwork_path()
    if not artwork_path then
        return nil
    end
    local artwork_name = artwork_path:match("([^/]+)%.xml$")
    return artwork_name
end

function artwork.get_template_resolution(xml_path)
    local xml_content = nativefs.read(xml_path)
    if not xml_content then
        return nil
    end

    local width, height = xml_content:match('<output [^>]*width="(%d+)"[^>]*height="(%d+)"')

    if width and height then
        return width .. "x" .. height
    end
    return nil
end

function artwork.get_output_types(xml_path)
    local xml_content = nativefs.read(xml_path)
    local result = {
        box = false,
        preview = false,
        splash = false
    }

    if not xml_content then
        return result
    end

    if xml_content:find('<output [^>]*type="cover"') then
        result.box = true
    end
    if xml_content:find('<output [^>]*type="screenshot"') then
        result.preview = true
    end
    if xml_content:find('<output [^>]*type="wheel"') then
        result.splash = true
    end

    return result
end

function artwork.copy_artwork_type(platform, game, media_path, copy_path, output_type)
    --[[
    platform -> nes | gb | gba | ...
    game -> "Super Mario World"
    media_path -> "data/output/{platform}/media"
    copy_path -> "/mnt/mmc/MUOS/info/catalogue/Platform Title/{type}"
    output_type -> box | preview | splash
  --]]

    -- Find scraped artwork in output folder
    local sanitized_game = game:gsub(":", "_")
    local scraped_art_path = string.format("%s/%s/%s.png", media_path, artwork.output_map[output_type], game)
    if not nativefs.getInfo(scraped_art_path) and sanitized_game ~= game then
        local alt_path = string.format("%s/%s/%s.png", media_path, artwork.output_map[output_type], sanitized_game)
        if nativefs.getInfo(alt_path) then
            scraped_art_path = alt_path
        end
    end

    -- Wait a bit for file to be fully written (sometimes filesystem is slow)
    local max_retries = 2
    local retry_delay = 0.05 -- 50ms
    local scraped_art = nil

    for i = 1, max_retries do
        scraped_art = nativefs.newFileData(scraped_art_path)
        if scraped_art then
            break
        end
        if i < max_retries then
            love.timer.sleep(retry_delay)
        end
    end

    if not scraped_art then
        log.write(string.format("Scraped artwork not found for output '%s' at path: %s",
            artwork.output_map[output_type], scraped_art_path))
        return
    end

    -- Ensure destination directory exists
    local dest_dir = string.format("%s/%s", copy_path, output_type)
    if not nativefs.getInfo(dest_dir) then
        nativefs.createDirectory(dest_dir)
    end
    -- Copy to catalogue
    local dest_file = string.format("%s/%s/%s.png", copy_path, output_type, game)
    local success, err = nativefs.write(dest_file, scraped_art)
    if err then
        log.write(string.format("Failed to write artwork to %s: %s", dest_file, err))
    else
        log.write(string.format("Successfully copied %s artwork to %s", output_type, dest_file))
        -- Verify file was written
        local verify = nativefs.getInfo(dest_file)
        if not verify then
            log.write(string.format("Warning: File write reported success but file not found: %s", dest_file))
        end
    end
end

function artwork.copy_to_catalogue(platform, game)
    log.write(string.format("Copying artwork for %s: %s", platform, game))
    local _, output_path = skyscraper_config:get_paths()
    local _, catalogue_path = user_config:get_paths()
    if output_path == nil or catalogue_path == nil then
        log.write("Missing paths from config")
        return
    end
    output_path = utils.strip_quotes(output_path)
    local platform_str = muos.platforms[platform]
    if not platform_str then
        log.write(string.format("Catalogue destination folder not found for platform: %s", platform))
        return
    end

    local pea_key = normalize_platform(platform)
    local media_path = string.format("%s/%s/media", output_path, pea_key)
    local copy_path = string.format("%s/%s", catalogue_path, platform_str)

    log.write(string.format("Source media path: %s", media_path))
    log.write(string.format("Destination catalogue path: %s", copy_path))

    -- Create platform directory and common subfolders if missing
    if not nativefs.getInfo(copy_path) then
        nativefs.createDirectory(copy_path)
    end
    local ensure_dirs = {"box", "preview", "splash", "text"}
    for _, d in ipairs(ensure_dirs) do
        local p = string.format("%s/%s", copy_path, d)
        if not nativefs.getInfo(p) then
            nativefs.createDirectory(p)
        end
    end

    -- Copy box/cover artwork
    artwork.copy_artwork_type(platform, game, media_path, copy_path, output_types.BOX)
    -- Copy preview artwork
    artwork.copy_artwork_type(platform, game, media_path, copy_path, output_types.PREVIEW)
    -- Copy splash artwork
    artwork.copy_artwork_type(platform, game, media_path, copy_path, output_types.SPLASH)

    -----------------------------
    -- Read Pegasus-formatted metadata
    -----------------------------
    local file = nativefs.read(string.format("%s/%s/metadata.pegasus.txt", output_path, platform))
    if file then
        local games = metadata.parse(file)
        if games then
            for _, entry in ipairs(games) do
                if entry.filename == game then
                    print(string.format("Writing desc for %s", game))
                    local _, err = nativefs.write(string.format("%s/text/%s.txt", copy_path, game),
                        string.format("%s\nGenre: %s", entry.description, entry.genre))
                    if err then
                        log.write(err)
                    end
                    break
                end
            end
        end
    else
        log.write("Failed to load metadata.pegasus.txt for " .. platform)
    end
end

function artwork.process_cached_by_platform(platform, cache_folder)
    local quick_id_entries = {}
    local cached_games = {}

    if not cache_folder then
        cache_folder = skyscraper_config:read("main", "cacheFolder")
        if not cache_folder or cache_folder == "\"\"" then
            return
        end
        cache_folder = utils.strip_quotes(cache_folder)
    end

    -- Read quickid and db files
    local quickid = nativefs.read(string.format("%s/%s/quickid.xml", cache_folder, platform))
    local db = nativefs.read(string.format("%s/%s/db.xml", cache_folder, platform))

    if not quickid or not db then
        log.write("Missing quickid.xml or db.xml for " .. platform)
        return
    end

    -- Parse quickid for ROM identifiers
    local lines = utils.split(quickid, "\n")
    for _, line in ipairs(lines) do
        if line:find("<quickid%s") then
            local filepath = line:match('filepath="([^"]+)"')
            if filepath then
                local filename = filepath:match("([^/]+)$")
                local id = line:match('id="([^"]+)"')
                if filename and id then
                    filename = xml_decode(filename)
                    id = xml_decode(id)
                    quick_id_entries[filename:lower()] = id -- Store filename in lowercase
                end
            end
        end
    end

    -- Parse db for resource matching
    local lines = utils.split(db, "\n")
    for _, line in ipairs(lines) do
        if line:find("<resource%s") then
            local id = line:match('id="([^"]+)"')
            local res_type = line:match('type="([^"]+)"')
            if id and res_type then
                id = xml_decode(id)
                res_type = xml_decode(res_type)
                if not cached_games[id] then
                    cached_games[id] = {}
                end
                cached_games[id][res_type] = true
            end
        end
    end

    -- Remove entries without matching resources
    for filename, id in pairs(quick_id_entries) do
        if not cached_games[id] then
            quick_id_entries[filename] = nil
        else
            -- Store the resource types for this game filename
            quick_id_entries[filename] = cached_games[id]
        end
    end


    -- Save entries globally (use lowercase platform ID for consistent lookup)
    local pea_key = normalize_platform(platform):lower() -- Normalize and lowercase platform key
    log.write(string.format("PLATFORM %s: Loaded %d cache entries (Pea key: %s)", platform, utils.table_length(quick_id_entries), pea_key))
    artwork.cached_game_ids[pea_key] = quick_id_entries
    log.write(string.format("Cached %d game entries for platform '%s'", utils.table_length(quick_id_entries), platform))
end

function artwork.process_cached_data()
    log.write("Processing cached data")
    artwork.cached_game_ids = {}
    local cache_folder = skyscraper_config:read("main", "cacheFolder")
    if not cache_folder then
        return
    end
    cache_folder = utils.strip_quotes(cache_folder)
    local items = nativefs.getDirectoryItems(cache_folder)
    if not items then
        return
    end

    for _, platform in ipairs(items) do
        artwork.process_cached_by_platform(platform)
    end


    log.write("Finished processing cached data")
end

-- Extract manual PDFs from cache and copy them to Game Manuals folder
-- Skyscraper stores manuals in cache/<platform>/manuals/<source>/<cache_id>.pdf
-- platform: Skyscraper platform ID (e.g., "nds")
-- Returns: number of manuals copied, number skipped
function artwork.extract_manuals(platform)
    local copied = 0
    local skipped = 0

    -- Get cache folder from Skyscraper config
    local cache_folder = skyscraper_config:read("main", "cacheFolder")
    if not cache_folder or cache_folder == "\"\"" then
        return copied, skipped
    end
    cache_folder = utils.strip_quotes(cache_folder)

    -- Build destination: /mnt/union/ROMS/Game Manuals/
    local rom_base, _ = config.user_config:get_paths()
    local dest_folder = string.format("%s/Game Manuals", rom_base)
    nativefs.createDirectory(dest_folder)

    -- Check if manuals subfolder exists in cache
    local manuals_cache_dir = string.format("%s/%s/manuals", cache_folder, platform)
    local manuals_dir_info = nativefs.getInfo(manuals_cache_dir)
    if not manuals_dir_info then
        return copied, skipped
    end

    -- Collect all manual files from source subdirectories (screenscraper/, thegamesdb/, etc.)
    local all_manual_files = {}
    local source_dirs = nativefs.getDirectoryItems(manuals_cache_dir)
    if not source_dirs then
        return copied, skipped
    end

    for _, source_dir in ipairs(source_dirs) do
        local source_path = string.format("%s/%s", manuals_cache_dir, source_dir)
        local source_info = nativefs.getInfo(source_path)
        if source_info and source_info.type == "directory" then
            local files = nativefs.getDirectoryItems(source_path)
            if files then
                for _, f in ipairs(files) do
                    table.insert(all_manual_files, {
                        path = string.format("%s/%s", source_path, f),
                        filename = f
                    })
                end
            end
        end
    end

    if #all_manual_files == 0 then
        return copied, skipped
    end

    -- Parse quickid.xml: map cache IDs -> ROM filenames
    local quickid_path = string.format("%s/%s/quickid.xml", cache_folder, platform)
    local quickid = nativefs.read(quickid_path)
    if not quickid then
        log.write(string.format("Missing quickid.xml for %s, cannot map manuals to ROMs", platform))
        return copied, skipped
    end

    local id_to_rom = {}
    for _, line in ipairs(utils.split(quickid, "\n")) do
        if line:find("<quickid%s") then
            local filepath = line:match('filepath="([^"]+)"')
            if filepath then
                local filename = filepath:match("([^/]+)$")
                local id = line:match('id="([^"]+)"')
                if filename and id then
                    id_to_rom[id] = xml_decode(filename) -- Decode filename here
                end
            end
        end
    end

    -- For each manual file in cache, match its ID to a ROM and copy
    for _, manual in ipairs(all_manual_files) do
        local cache_id = manual.filename:match("^(.+)%.[^.]+$") or manual.filename
        local rom_filename = id_to_rom[cache_id]

        if rom_filename then
            local rom_name = utils.get_filename(rom_filename)
            local dest_path = string.format("%s/%s.pdf", dest_folder, rom_name)

            local exists = nativefs.getInfo(dest_path)
            if exists then
                skipped = skipped + 1
            else
                local content = nativefs.read(manual.path)
                if content then
                    local ok, err = nativefs.write(dest_path, content)
                    if ok then
                        copied = copied + 1
                        log.write(string.format("Copied manual to %s", dest_path))
                    else
                        log.write(string.format("Failed to write manual to %s: %s", dest_path, err or "unknown"))
                    end
                else
                    log.write(string.format("Failed to read manual cache file: %s", manual.path))
                end
            end
        end
    end

    log.write(string.format("Manual extraction for %s: %d copied, %d skipped", platform, copied, skipped))
    return copied, skipped
end

return artwork


