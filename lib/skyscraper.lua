-- Normalize internal or umbrella platform keys to peas/Skyscraper keys
local function normalize_platform(platform)
    if not platform then
        return platform
    end
    -- Map internal distinctions to real Skyscraper platform IDs
    local map = {
        ["pcengine_"] = "pcengine", -- SuperGrafx shares Skyscraper platform with PC Engine
        ["coleco_"] = "coleco" -- Umbrella SVI - ColecoVision - SG1000 uses coleco in Skyscraper
    }
    local normalized = map[platform] or platform
    return (type(normalized) == "string") and normalized:lower() or normalized
end

-- Escape special shell characters in filenames
-- This is critical for games with parentheses, apostrophes, etc.
local function escape_shell_arg(arg)
    if not arg then
        return arg
    end
    -- For use with double quotes: escape backslash, double quote, dollar, backtick, and newline
    -- Parentheses don't need escaping inside double quotes
    local escaped = arg:gsub('\\', '\\\\') -- Backslash first
    escaped = escaped:gsub('"', '\\"') -- Double quotes
    escaped = escaped:gsub('%$', '\\$') -- Dollar signs
    escaped = escaped:gsub('`', '\\`') -- Backticks
    escaped = escaped:gsub('\n', '\\n') -- Newlines
    return escaped
end

require("globals")

local json = require("lib.json")
local log = require("lib.log")
local channels = require("lib.backend.channels")
local utils = require("helpers.utils")
local skyscraper_config = require("helpers.config").skyscraper_config

local skyscraper = {
    base_command = "./Skyscraper",
    module = "screenscraper",
    config_path = "",
    peas_json = {}
}

local cache_thread
local gen_threads = {}  -- Pool of generation threads for true parallel artwork generation
local gen_thread_count = 1  -- Will be updated from config

local function push_cache_command(command)
    if channels.SKYSCRAPER_INPUT then
        channels.SKYSCRAPER_INPUT:push(command)
    end
end

local function push_gen_command(command)
    if channels.SKYSCRAPER_GEN_INPUT then
        channels.SKYSCRAPER_GEN_INPUT:push(command)
    end
end

local function create_threads()
    log.write(string.format("Creating Skyscraper threads (%d generation workers)", gen_thread_count))
    cache_thread = love.thread.newThread("lib/backend/skyscraper_backend.lua")
    gen_threads = {}
    for i = 1, gen_thread_count do
        gen_threads[i] = love.thread.newThread("lib/backend/skyscraper_generate_backend.lua")
    end
    cache_thread:start()
    for i = 1, #gen_threads do
        gen_threads[i]:start()
    end
    log.write(string.format("Skyscraper threads started (%d generation workers)", #gen_threads))
end

function skyscraper.restart_threads()
    log.write("Restarting Skyscraper threads")

    -- CRITICAL: Kill any running Skyscraper processes FIRST
    -- This forces io.popen() to return in threads that are blocked on it
    os.execute("killall -9 Skyscraper Skyscraper.aarch64 2>/dev/null")

    -- Set abort flag so threads know to stop
    channels.SKYSCRAPER_ABORT:push(true)

    -- Clear all channels to remove any pending work
    channels.SKYSCRAPER_INPUT:clear()
    channels.SKYSCRAPER_GEN_INPUT:clear()
    channels.SKYSCRAPER_GAME_QUEUE:clear()
    channels.SKYSCRAPER_OUTPUT:clear()
    channels.SKYSCRAPER_GEN_OUTPUT:clear()

    -- Send exit signals to cache thread and ALL gen threads
    channels.SKYSCRAPER_INPUT:push({
        exit = true
    })
    for i = 1, #gen_threads do
        channels.SKYSCRAPER_GEN_INPUT:push({
            exit = true
        })
    end

    -- Wait for threads to actually terminate (up to 3 seconds - io.popen may take time)
    local timeout = 3.0
    local start_time = love.timer.getTime()
    while love.timer.getTime() - start_time < timeout do
        local all_stopped = true
        if cache_thread and cache_thread:isRunning() then
            all_stopped = false
            channels.SKYSCRAPER_INPUT:push({ exit = true })
        end
        for i = 1, #gen_threads do
            if gen_threads[i] and gen_threads[i]:isRunning() then
                all_stopped = false
                channels.SKYSCRAPER_GEN_INPUT:push({ exit = true })
            end
        end

        if all_stopped then
            log.write("All threads terminated successfully")
            break
        end

        love.timer.sleep(0.1)
    end

    -- Check for errors
    if cache_thread then
        local err = cache_thread:getError()
        if err then
            log.write("Cache thread error: " .. err)
        end
    end
    for i = 1, #gen_threads do
        if gen_threads[i] then
            local err = gen_threads[i]:getError()
            if err then
                log.write(string.format("Gen thread %d error: %s", i, err))
            end
        end
    end

    -- Clear ALL channels again (completely clean state)
    channels.SKYSCRAPER_ABORT:clear()
    channels.SKYSCRAPER_INPUT:clear()
    channels.SKYSCRAPER_GEN_INPUT:clear()
    channels.SKYSCRAPER_GAME_QUEUE:clear()
    channels.SKYSCRAPER_OUTPUT:clear()
    channels.SKYSCRAPER_GEN_OUTPUT:clear()

    -- Create and start new threads
    create_threads()
    log.write("Skyscraper threads restarted successfully")
end

-- Returns the preferred module for a given platform
-- Ports always use TheGamesDB, other platforms respect Advanced Tools selection
local function get_default_module_for(platform)
    local pea_key = normalize_platform(platform)

    -- Ports: use IGDB if explicitly selected, otherwise fall back to TheGamesDB
    -- (ScreenScraper lacks ports/PC game coverage)
    if pea_key == "ports" or pea_key == "PORTS" then
        if skyscraper.module == "igdb" then
            return "igdb"
        end
        return "thegamesdb"
    end

    -- Use user's Advanced Tools selection if set
    if skyscraper.module and skyscraper.module ~= "" then
        return skyscraper.module
    end

    -- Fall back to peas.json scraper list
    local entry = skyscraper.peas_json[pea_key]
    local scrapers = entry and entry.scrapers
    if scrapers and #scrapers > 0 then
        -- Prefer ScreenScraper when available for broader coverage
        for _, s in ipairs(scrapers) do
            if s == "screenscraper" then
                return "screenscraper"
            end
        end
        -- Fallback to the first declared scraper for the platform
        return scrapers[1]
    end
    -- Global default fallback
    return "screenscraper"
end

function skyscraper.init(config_path, binary)
    log.write("Initializing Skyscraper")
    skyscraper.config_path = WORK_DIR .. "/" .. config_path
    skyscraper.base_command = "env QT_QPA_PLATFORM=offscreen NO_COLOR=1 ./" .. binary

    -- Load saved scraper module from config
    local configs = require("helpers.config")
    local user_config = configs.user_config
    if user_config then
        local saved_module = user_config:read("main", "scraperModule")
        if saved_module and saved_module ~= "" then
            skyscraper.module = saved_module
            log.write("Loaded scraper module preference: " .. saved_module)
        end

        -- Read concurrency setting to determine how many generation threads to spawn
        local concurrent_cfg = user_config:read("main", "concurrentGeneration")
        local concurrent = tonumber(concurrent_cfg or "") or 3
        if concurrent < 1 then concurrent = 1 end
        if concurrent > 8 then concurrent = 8 end
        gen_thread_count = concurrent
    end

    -- Create and start threads (spawns gen_thread_count generation workers)
    create_threads()

    -- Load peas.json file
    local peas_file = nativefs.read(string.format("%s/static/.skyscraper/peas.json", WORK_DIR))
    if peas_file then
        skyscraper.peas_json = json.decode(peas_file)
    else
        log.write("Unable to load peas.json file")
    end

    push_cache_command({
        command = string.format("%s -v", skyscraper.base_command),
        version = true
    })

    -- Check if fake-rom artwork is missing and initialize if necessary
    local sample_check = WORK_DIR .. "/sample/media/covers/fake-rom.png"
    local info = nativefs.getInfo(sample_check)
    if not info then
        local saved_preset = "Streets of Rage"
        if user_config then
            local p = user_config:read("main", "samplePreset")
            if p and p ~= "" then
                saved_preset = p
            end
        end
        log.write("Fake-rom artwork missing, initializing with preset: " .. saved_preset)
        if skyscraper.apply_sample_preset(saved_preset) then
            local artwork_xml = "box2d"
            if skyscraper_config then
                local saved = skyscraper_config:read("main", "artworkXml")
                if saved and saved ~= "" then
                    local utils = require("helpers.utils")
                    artwork_xml = utils.strip_quotes(saved)
                end
            end
            skyscraper.update_sample(artwork_xml)
        end
    end

end

function skyscraper.get_gen_thread_count()
    return gen_thread_count
end

-- Shutdown function to clean up backend processes on app exit
function skyscraper.shutdown()
    log.write("Shutting down Skyscraper backend")

    -- Send abort signal to each generation thread
    for i = 1, #gen_threads do
        channels.SKYSCRAPER_ABORT:push({ abort = true })
    end

    -- Kill any running Skyscraper processes
    os.execute("killall -9 Skyscraper.aarch64 2>/dev/null")
    os.execute("killall -9 Skyscraper 2>/dev/null")

    -- Clear all channels to unblock threads
    channels.SKYSCRAPER_INPUT:clear()
    channels.SKYSCRAPER_GEN_INPUT:clear()
    channels.SKYSCRAPER_GAME_QUEUE:clear()
    channels.SKYSCRAPER_OUTPUT:clear()
    channels.SKYSCRAPER_GEN_OUTPUT:clear()
end

function skyscraper.filename_matches_extension(filename, platform)
    local pea_key = normalize_platform(platform)
    local formats = skyscraper.peas_json[pea_key] and skyscraper.peas_json[pea_key].formats
    if not formats then
        log.write("Unable to determine file formats for platform " .. (pea_key or tostring(platform)))
        return true
    end

    -- .zip and .7z are added by default
    -- https://gemba.github.io/skyscraper/PLATFORMS/#sample-usecase-adding-platform-satellaview
    local match_patterns = {'%.*%.zip$', '%.*%.7z$'}
    -- Heuristic: accept common DOSBox Pure/SVN formats when platform is 'pc'
    if pea_key == 'pc' then
        local extra_pc = {'%.*%.exe$', '%.*%.com$', '%.*%.bat$', '%.*%.dosz$', '%.*%.iso$', '%.*%.img$', '%.*%.cue$',
                          '%.*%.m3u$'}
        for _, p in ipairs(extra_pc) do
            table.insert(match_patterns, p)
        end
    end
    -- Convert patterns to Lua-compatible patterns
    for _, pattern in ipairs(formats) do
        local lua_pattern = pattern:gsub("%*", ".*"):gsub("%.", "%%.")
        -- Add '$' to ensure the pattern matches the end of the string
        lua_pattern = lua_pattern .. "$"
        table.insert(match_patterns, lua_pattern)
    end

    -- Check if a file matches any of the patterns
    local lower_filename = filename:lower()
    for _, pattern in ipairs(match_patterns) do
        if lower_filename:match(pattern:lower()) then
            return true
        end
    end

    return false
end

local function generate_command(config)
    if config.fetch == nil then
        config.fetch = false
    end
    if config.use_config == nil then
        config.use_config = true
    end
    if config.module == nil then
        config.module = skyscraper.module
    end

    local command = ""
    if config.platform then
        command = string.format('%s -p %s', command, normalize_platform(config.platform))
    end
    if config.fetch then
        command = string.format('%s -s %s', command, config.module)
        command = string.format('%s --verbosity 1 --stderr', command)
    end
    if config.use_config then
        command = string.format('%s -c "%s"', command, skyscraper.config_path)
    else
        command = string.format('%s -c /dev/null', command)
    end
    if config.cache then
        command = string.format('%s -d "%s"', command, config.cache)
    end
    if config.input then
        command = string.format('%s -i "%s"', command, config.input)
    end
    if config.rom then
        -- Escape special characters for ROM filenames to handle characters
        -- like parentheses, which are common in ROM names (e.g., "Super Metroid (USA).sfc")
        local escaped_rom = escape_shell_arg(config.rom)
        -- Pass the ROM relative path as a positional argument at the end of the options
        command = string.format('%s "%s"', command, escaped_rom)
    end
    if config.include_from then
        command = string.format('%s --includefrom "%s"', command, config.include_from)
    end
    if config.artwork then
        command = string.format('%s -a "%s"', command, config.artwork)
    end
    if config.flags and next(config.flags) then
        command = string.format('%s --flags %s', command, table.concat(config.flags, ","))
    end
    -- Custom query for refine search feature (Skyscraper --query option)
    if config.query and config.query ~= "" then
        -- Convert spaces to + for URL-style query, escape special characters
        local query_str = config.query:gsub(" ", "+")
        query_str = escape_shell_arg(query_str)
        command = string.format('%s --query "%s"', command, query_str)
    end
    -- Add startat flag for resuming
    if config.start_at then
        local escaped_start = escape_shell_arg(config.start_at)
        command = string.format('%s --startat "%s"', command, escaped_start)
    end
    -- Force regeneration of media even if it already exists
    if config.refresh then
        command = string.format('%s --refresh', command)
    end
    if config.output then
        command = string.format('%s -o "%s"', command, config.output)
    end

    -- Use 'pegasus' frontend for simpler gamelist generation
    command = string.format('%s -f pegasus', command)

    -- Performance optimization: If running multiple parallel workers, 
    -- force each Skyscraper process to be single-threaded to avoid core contention.
    -- (Only for generation phase; fetch can still use multiple threads for networking).
    if not config.fetch and gen_thread_count > 1 then
        command = string.format('%s -t 1', command)
    end

    -- When using --query, Skyscraper requires the filename as a positional argument at the end
    -- Otherwise the query is ignored. See: https://gemba.github.io/skyscraper/CLIHELP/#-query-string
    if config.query and config.query ~= "" and config.input and config.rom then
        local full_rom_path = string.format('%s/%s', config.input, config.rom)
        local escaped_path = escape_shell_arg(full_rom_path)
        command = string.format('%s "%s"', command, escaped_path)
    end

    -- Log the command for debugging
    log.write(string.format("Generated command: %s", command))
    return command
end

function skyscraper.run(command, input_folder, platform, op, game)
    platform = platform or "none"
    op = op or "generate"
    game = game or "none"
    if op == "generate" then
        push_gen_command({
            command = skyscraper.base_command .. command,
            platform = platform,
            op = op,
            game = game,
            input_folder = input_folder
        })
    else
        push_cache_command({
            command = skyscraper.base_command .. command,
            platform = platform,
            op = op,
            game = game,
            input_folder = input_folder
        })
    end
end

function skyscraper.change_artwork(artworkXml)
    skyscraper_config:insert("main", "artworkXml", '"' .. artworkXml .. '"')
    skyscraper_config:save()
end

function skyscraper.update_sample(artwork_path)
    local command = generate_command({
        use_config = false,
        platform = "megadrive",
        cache = WORK_DIR .. "/sample",
        input = WORK_DIR .. "/sample",
        artwork = artwork_path,
        flags = {"unattend"},
        refresh = true,
        output = WORK_DIR .. "/sample/media"
    })
    skyscraper.run(command, "N/A", "N/A", "generate", "fake-rom")
end

function skyscraper.custom_update_artwork(platform, cache, input, artwork)
    local command = generate_command({
        use_config = false,
        platform = platform,
        cache = cache,
        input = input,
        artwork = artwork,
        flags = {"unattend"}
    })
    skyscraper.run(command)
end

function skyscraper.fetch_artwork(rom_path, input_folder, platform, start_at, include_from, refresh)
    local flags = {"unattend"}
    if not refresh then
        table.insert(flags, "onlymissing")
    end
    local videos_cfg = skyscraper_config:read("main", "videos") or "false"
    local videos_enabled = (utils.strip_quotes(videos_cfg) == "true")
    if videos_enabled then
        table.insert(flags, "videos")
    end

    local command = generate_command({
        platform = platform,
        input = rom_path,
        fetch = true,
        module = get_default_module_for(platform),
        flags = flags,
        start_at = start_at,
        include_from = include_from,
        refresh = refresh
    })
    skyscraper.run(command, input_folder, platform, "update")
end

function skyscraper.update_artwork(rom_path, rom, input_folder, platform, artwork)
    local artwork = WORK_DIR .. "/templates/" .. artwork .. ".xml"

    local update_command = generate_command({
        platform = platform,
        input = rom_path,
        artwork = artwork,
        rom = rom,
        refresh = true
    })
    skyscraper.run(update_command, input_folder, platform, "generate", rom)
end

function skyscraper.update_artwork_chunk(rom_path, include_file, input_folder, platform, artwork, chunk_id)
    local artwork = WORK_DIR .. "/templates/" .. artwork .. ".xml"

    local update_command = generate_command({
        platform = platform,
        input = rom_path,
        artwork = artwork,
        include_from = include_file,
        refresh = true
    })
    skyscraper.run(update_command, input_folder, platform, "generate", "chunk-" .. chunk_id)
end

function skyscraper.fetch_single(rom_path, rom, input_folder, platform, flags, query)
    flags = flags or {"unattend"}

    local videos_cfg = skyscraper_config:read("main", "videos") or "false"
    local videos_enabled = (utils.strip_quotes(videos_cfg) == "true")
    if videos_enabled then
        local has_videos = false
        for _, f in ipairs(flags) do
            if f == "videos" then
                has_videos = true
                break
            end
        end
        if not has_videos then
            table.insert(flags, "videos")
        end
    end

    local fetch_command = generate_command({
        platform = platform,
        input = rom_path,
        fetch = true,
        module = get_default_module_for(platform),
        rom = rom,
        flags = flags,
        query = query, -- Custom search query for refine search
        refresh = true  -- Force refresh to fetch newly enabled resource types like videos
    })
    skyscraper.run(fetch_command, input_folder, platform, "fetch", rom)
end

function skyscraper.custom_import(rom_path, platform)
    local command = generate_command({
        platform = platform,
        input = rom_path,
        module = "import",
        fetch = true
    })
    skyscraper.run(command, "N/A", platform, "import")
end

-- Fetch game manual (PDF) for a single ROM from ScreenScraper
-- Fetch game manual (PDF) for a single ROM from ScreenScraper
function skyscraper.fetch_single_manual(rom_path, rom, input_folder, platform, query)
    local flags = {"unattend", "manuals"}
    local videos_cfg = skyscraper_config:read("main", "videos") or "false"
    local videos_enabled = (utils.strip_quotes(videos_cfg) == "true")
    if videos_enabled then
        table.insert(flags, "videos")
    end

    local command = generate_command({
        platform = platform,
        input = rom_path,
        fetch = true,
        module = "screenscraper",
        refresh = true,
        rom = rom,
        flags = flags,
        query = query
    })
    skyscraper.run(command, input_folder, platform, "fetch", rom)
end

function skyscraper.get_sample_presets()
    local presets_dir = WORK_DIR .. "/sample/presets"
    return nativefs.getDirectoryItems(presets_dir) or {}
end

function skyscraper.apply_sample_preset(preset_name)
    local preset_dir = WORK_DIR .. "/sample/presets/" .. preset_name
    local types = {"cover", "marquee", "screenshot", "texture", "wheel"}
    
    for _, t in ipairs(types) do
        local src = preset_dir .. "/" .. t .. ".png"
        local dest_dir = WORK_DIR .. "/sample/" .. t .. "s/screenscraper"
        local dest = dest_dir .. "/fake-rom"
        
        -- Copy file if it exists
        local info = nativefs.getInfo(src)
        if info then
             local data = nativefs.read(src)
             if data then
                 -- Ensure destination directory exists
                 nativefs.createDirectory(WORK_DIR .. "/sample/" .. t .. "s")
                 nativefs.createDirectory(dest_dir)
                 nativefs.write(dest, data)
             end
        end
    end

    -- Update db.xml
    local db_path = WORK_DIR .. "/sample/db.xml"
    local db_content = nativefs.read(db_path)
    if db_content then
        -- Find the title resource line and replace its content
        local pattern = '(<resource [^>]*type="title"[^>]*>)(.-)(</resource>)'
        local new_content = db_content:gsub(pattern, function(a, b, c)
            return a .. preset_name .. c
        end)
        nativefs.write(db_path, new_content)
    end
    
    return true
end

function skyscraper.get_cache_platforms()
    local cache_dir = WORK_DIR .. "/data/cache"
    local items = nativefs.getDirectoryItems(cache_dir)
    local platforms = {}
    for _, item in ipairs(items or {}) do
        local info = nativefs.getInfo(cache_dir .. "/" .. item)
        if info and info.type == "directory" then
            table.insert(platforms, item)
        end
    end
    table.sort(platforms)
    return platforms
end

function skyscraper.parse_cache_db(platform)
    local db_path = WORK_DIR .. "/data/cache/" .. platform .. "/db.xml"
    if not nativefs.getInfo(db_path) then return {} end
    
    local f = nativefs.newFile(db_path)
    if not f:open("r") then return {} end
    local content = f:read()
    f:close()

    local titles = {}
    -- Matches <resource id="HASH" type="title" ... >TITLE</resource>
    for id, title in content:gmatch('<resource id="([^"]+)" type="title"[^>]*>([^<]+)</resource>') do
        titles[id] = title
    end
    return titles
end

function skyscraper.get_cache_roms(platform)
    local titles = skyscraper.parse_cache_db(platform)
    local roms = {}
    
    -- Check all source subfolders in covers/ to find which hashes exist
    local covers_base = WORK_DIR .. "/data/cache/" .. platform .. "/covers"
    local source_modules = nativefs.getDirectoryItems(covers_base)
    local existing_hashes = {}
    for _, module in ipairs(source_modules or {}) do
        local items = nativefs.getDirectoryItems(covers_base .. "/" .. module)
        for _, h in ipairs(items or {}) do
            existing_hashes[h] = true
        end
    end

    for id, title in pairs(titles) do
        if existing_hashes[id] then
            table.insert(roms, { title = title, hash = id })
        end
    end
    
    table.sort(roms, function(a, b) return a.title:lower() < b.title:lower() end)
    return roms
end

-- Internal helper to find media across various Skyscraper modules
local function find_media_in_cache(platform, type_name, hash)
    local type_to_folder = {
        cover = "covers",
        marquee = "marquees",
        screenshot = "screenshots",
        texture = "textures",
        wheel = "wheels"
    }
    local folder_name = type_to_folder[type_name]
    if not folder_name then return nil end
    
    local base_path = WORK_DIR .. "/data/cache/" .. platform .. "/" .. folder_name
    if not nativefs.getInfo(base_path) then return nil end
    
    -- Priority modules
    local modules = {"screenscraper", "thegamesdb", "igdb", "local", "raw", "import"}
    
    for _, mod in ipairs(modules) do
        local path = base_path .. "/" .. mod .. "/" .. hash
        if nativefs.getInfo(path) then
            return path
        end
    end
    
    -- Fallback: check any other subfolders
    local all_subs = nativefs.getDirectoryItems(base_path)
    for _, sub in ipairs(all_subs or {}) do
        -- Skip if we already checked it in priority
        local checked = false
        for _, p in ipairs(modules) do if p == sub then checked = true break end end
        
        if not checked then
            local path = base_path .. "/" .. sub .. "/" .. hash
            if nativefs.getInfo(path) then
                return path
            end
        end
    end
    
    return nil
end

function skyscraper.get_missing_media(platform, hash)
    local missing = {}
    local order = {"cover", "marquee", "screenshot", "texture", "wheel"}
    for _, type in ipairs(order) do
        if not find_media_in_cache(platform, type, hash) then
            table.insert(missing, type)
        end
    end
    return missing
end

function skyscraper.create_preset(platform, hash, preset_name)
    local preset_dir = WORK_DIR .. "/sample/presets/" .. preset_name
    if not nativefs.createDirectory(preset_dir) then
        -- Second attempt in case it already exists or simple creation fails
        local info = nativefs.getInfo(preset_dir)
        if not (info and info.type == "directory") then
            return false
        end
    end
    
    local types = {"cover", "marquee", "screenshot", "texture", "wheel"}
    
    for _, type in ipairs(types) do
        local src = find_media_in_cache(platform, type, hash)
        if src then
            local dest = preset_dir .. "/" .. type .. ".png"
            local data = nativefs.read(src)
            if data then
                nativefs.write(dest, data)
            end
        end
    end
    return true
end

function skyscraper.delete_preset(preset_name)
    -- Protect the default preset
    if preset_name == "Streets of Rage" then return false end
    
    local preset_dir = WORK_DIR .. "/sample/presets/" .. preset_name
    local info = nativefs.getInfo(preset_dir)
    if not info then return false end
    
    -- Use rm -rf for recursive deletion on Linux/MuOS
    os.execute(string.format('rm -rf "%s"', preset_dir))
    return true
end

skyscraper.get_module_name = get_default_module_for


return skyscraper
