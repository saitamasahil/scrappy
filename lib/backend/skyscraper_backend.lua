require("globals")
local parser = require("lib.parser")
local log = require("lib.log")
local channels = require("lib.backend.channels")
local pprint = require("lib.pprint")
local utils = require("helpers.utils")
local wifi = require("helpers.wifi")
local socket = require("socket")
local configs = require("helpers.config")
local user_config = configs.user_config

-- Helper to check if offline mode is enabled
local function is_offline_mode()
    return (user_config:read("main", "offlineMode") == "1")
end

local function log_version(output)
    if not output then
        log.write("Failed to run Skyscraper")
        return
    end

    for _, line in ipairs(output) do
        -- Attempt to parse errors
        local _, err = parser.parse(line)
        if err then
            log.write("Failed to start Skyscraper: " .. err, "skyscraper")
            break
        end

        -- Check for version pattern in the line
        local version = line:match("(%d+%.%d+%.%d+)")
        if version then
            log.write(string.format("Skyscraper version: %s\n", version))
            break
        end
    end
end

local function emit_ready(game, platform, input_folder, skipped)
    channels.SKYSCRAPER_GAME_QUEUE:push({
        game = game,
        platform = platform,
        input_folder = input_folder,
        skipped = skipped
    })
end

local function run_fetch_command(cmd, current_platform, input_folder, op, game_override, idx, total_games)
    local stderr_to_stdout = " 2>&1"
    local output = io.popen("nice -n 19 " .. cmd .. stderr_to_stdout)
    if not output then
        log.write("Failed to run Skyscraper")
        channels.SKYSCRAPER_OUTPUT:push({
            data = {},
            error = "Failed to run Skyscraper",
            loading = false
        })
        return false, false, true, false
    end

    local parsed = false
    local retriable_error = false
    local fatal_error = false
    local aborted = false
    local line_count = 0
    local games_emitted = 0

    for line in output:lines() do
        line_count = line_count + 1

        -- Abort check every line
        local abort_sig = channels.SKYSCRAPER_ABORT:pop()
        if abort_sig and (abort_sig == true or abort_sig.abort) then
            aborted = true
            log.write("[fetch] Abort signal received, killing process")
            channels.SKYSCRAPER_OUTPUT:push({
                log = "[fetch] Aborted by user"
            })
            if output then
                pcall(output.close, output)
                output = nil
            end
            os.execute("killall -9 Skyscraper Skyscraper.aarch64 2>/dev/null")
            break
        end

        -- Network check during scraping (skip in offline mode)
        if not is_offline_mode() and not wifi.is_connected() then
            aborted = true
            log.write("Network disconnected during scraping")
            channels.SKYSCRAPER_OUTPUT:push({
                log = "[fetch] Network disconnected. Stopping scrape.",
                error = "Network disconnected",
                loading = false
            })
            if output then
                pcall(output.close, output)
                output = nil
            end
            os.execute("killall -9 Skyscraper Skyscraper.aarch64 2>/dev/null")
            break
        end

        line = utils.strip_ansi_colors(line)

        -- If running in per-game incremental mode, adjust #1/1 to true total progress #idx/total_games
        if total_games and total_games > 1 and line:find("#1/1") then
            line = line:gsub("#1/1", string.format("#%d/%d", idx, total_games))
        end

        -- Filter repetitive startup/shutdown boilerplate logs in incremental multi-game mode
        local is_boilerplate = false
        if total_games and total_games > 1 then
            if idx > 1 and (
                line:find("Running Skyscraper") or
                line:find("Fetching limits for user") or
                line:find("Looking for optional") or
                line:find("Starting scraping run") or
                line:find("Sit back, relax")
            ) then
                is_boilerplate = true
            end
            if idx < total_games and (
                line:find("Resource gathering run completed") or
                line:find("And here are some neat stats") or
                line:find("Total completion time") or
                line:find("Average search match") or
                line:find("Average entry completeness") or
                line:find("Total number of games") or
                line:find("Successfully processed games") or
                line:find("Skipped games") or
                line:find("Writing quick id xml") or
                line:find("resources to cache, please wait")
            ) then
                is_boilerplate = true
            end
        end

        -- RUNNING TASK; PUSH OUTPUT
        if (op == "update" or op == "import") and not is_boilerplate then
            channels.TASK_OUTPUT:push({
                output = line,
                error = nil
            })
        end

        local res, error, skipped, rtype = parser.parse(line)
        if res ~= nil or error then
            parsed = true
        end
        if res ~= nil then
            if not is_boilerplate or rtype == "game" then
                log.write(string.format("[fetch] %s", line), "skyscraper")
                channels.SKYSCRAPER_OUTPUT:push({
                    log = string.format("[fetch] %s", line)
                })
            end
            if rtype == "game" then
                games_emitted = games_emitted + 1
                emit_ready(res, current_platform, input_folder, skipped)
            end
        end

        if res == nil and (error == nil or error == "") and not is_boilerplate then 
            log.write(string.format("[fetch:raw] %s", line), "skyscraper") 
        end

        if error ~= nil and error ~= "" then
            log.write("ERROR: " .. error, "skyscraper")
            channels.SKYSCRAPER_OUTPUT:push({
                data = {},
                error = error,
                loading = false
            })
            if error:lower():find("invalid/empty json") then
                retriable_error = true
            else
                fatal_error = true
            end
            break
        end
    end

    if output then
        pcall(output.close, output)
        output = nil
    end

    -- For single-game scrape runs, if process ended without emitting a game result,
    -- emit a skipped event so UI/state does not hang indefinitely.
    local game_name = game_override
    if game_name and game_name ~= "none" and games_emitted == 0 and not aborted then
        emit_ready(game_name, current_platform, input_folder, true)
    end

    return (not aborted and not fatal_error), aborted, fatal_error, retriable_error
end

while true do
    -- Demand a table with command, platform, type, and game from SKYSCRAPER_INPUT
    local input_data = channels.SKYSCRAPER_INPUT:demand()

    -- Check for exit signal to terminate thread gracefully
    if input_data.exit then
        log.write("[fetch] Exit signal received, terminating thread")
        break
    end

    -- Extract the command, platform, type, and game
    local command = input_data.command
    local current_platform = input_data.platform
    local input_folder = input_data.input_folder
    local op = input_data.op

    log.write("Starting Skyscraper, please wait...")

    -- Check network before starting command (skip in offline mode)
    if not is_offline_mode() and not wifi.is_connected() then
        log.write("Network disconnected, aborting scrape")
        channels.SKYSCRAPER_OUTPUT:push({
            log = "[fetch] Network disconnected. Please connect to a network and try again.",
            error = "Network not connected",
            loading = false
        })
    else
        if current_platform then
            channels.SKYSCRAPER_OUTPUT:push({
                log = "[fetch] Starting Skyscraper for \"" .. current_platform .. "\", please wait..."
            })
        end

        log.write(string.format("Running command: %s", command))
        log.write(string.format("Platform: %s | Game: %s", current_platform or "none", input_data.game or "none"))

        -- Log API/network context
        if command:find("screenscraper") then
            log.write("[fetch] Using ScreenScraper API - network delays or rate limits may occur")
        end

        if current_platform and current_platform ~= "none" then
            channels.SKYSCRAPER_OUTPUT:push({
                log = string.format("[fetch] Starting platform %s", current_platform),
                platform_started = current_platform
            })
        end

        -- Special command: version check
        if input_data.version then
            local output = io.popen("nice -n 19 " .. command .. " 2>&1")
            if output then
                local result = output:read("*a")
                pcall(output.close, output)
                local lines = utils.split(result, "\n")
                log_version(lines)
            end
        else
            -- Check if include_from file is provided with multiple ROMs to scrape
            local include_file = command:match('%-%-includefrom "([^"]+)"')
            local rom_list = {}
            if include_file then
                local f = io.open(include_file, "r")
                if f then
                    for rom_line in f:lines() do
                        rom_line = rom_line:gsub("^%s*(.-)%s*$", "%1")
                        if rom_line ~= "" then
                            table.insert(rom_list, rom_line)
                        end
                    end
                    f:close()
                end
            end

            local aborted = false

            if #rom_list > 1 then
                log.write(string.format("[fetch] Auto-saving DB per game for %d games in platform '%s'", #rom_list, current_platform or "none"))
                local temp_single_include = "/tmp/scrappy_fetch_single_game.txt"
                local all_completed = true

                for idx, single_rom in ipairs(rom_list) do
                    -- Abort check before starting each game
                    local abort_sig = channels.SKYSCRAPER_ABORT:pop()
                    if abort_sig and (abort_sig == true or abort_sig.abort) then
                        aborted = true
                        all_completed = false
                        break
                    end
                    if not is_offline_mode() and not wifi.is_connected() then
                        aborted = true
                        all_completed = false
                        log.write("Network disconnected during scraping")
                        channels.SKYSCRAPER_OUTPUT:push({
                            log = "[fetch] Network disconnected. Stopping scrape.",
                            error = "Network disconnected",
                            loading = false
                        })
                        break
                    end

                    -- Write single ROM to temporary include file
                    local sf = io.open(temp_single_include, "w")
                    if sf then
                        sf:write(single_rom .. "\n")
                        sf:close()
                    end

                    -- Replace includefrom parameter with the single-game include file
                    local single_cmd = command:gsub('%-%-includefrom "[^"]+"', string.format('--includefrom "%s"', temp_single_include))

                    local success, was_aborted, was_fatal, was_retriable = run_fetch_command(
                        single_cmd, current_platform, input_folder, op, single_rom, idx, #rom_list
                    )

                    if was_aborted then
                        aborted = true
                        all_completed = false
                        break
                    end
                end

                pcall(os.remove, temp_single_include)

                if current_platform and not aborted and all_completed then
                    channels.SKYSCRAPER_OUTPUT:push({
                        log = string.format("[fetch] Platform %s completed", current_platform)
                    })
                end
            else
                -- Single game or non-includefrom command: run directly
                local success, was_aborted, was_fatal, was_retriable = run_fetch_command(
                    command, current_platform, input_folder, op, input_data.game, 1, 1
                )

                if current_platform and not was_aborted and not was_fatal then
                    channels.SKYSCRAPER_OUTPUT:push({
                        log = string.format("[fetch] Platform %s completed", current_platform)
                    })
                end
            end
        end
    end
end

function love.threaderror(thread, errorstr)
    print(errorstr)
    log.write(errorstr)
end
