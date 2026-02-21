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

while true do
    ::continue::
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

    -- Check WiFi before starting command (skip in offline mode)
    if not is_offline_mode() and not wifi.is_connected() then
        log.write("WiFi disconnected, aborting scrape")
        channels.SKYSCRAPER_OUTPUT:push({
            log = "[fetch] WiFi disconnected. Please connect to WiFi and try again.",
            error = "WiFi not connected",
            loading = false
        })
        goto continue
    end

    if current_platform then
        channels.SKYSCRAPER_OUTPUT:push({
            log = "[fetch] Starting Skyscraper for \"" .. current_platform .. "\", please wait..."
        })
    end

    local attempts, max_attempts = 0, 3
    local retry_delay_secs = 5
    local aborted = false
    while attempts < max_attempts do
        attempts = attempts + 1
        local stderr_to_stdout = " 2>&1"

        log.write(string.format("Running command: %s", command))
        log.write(string.format("Platform: %s | Game: %s", current_platform or "none", input_data.game or "none"))

        -- Log API/network context
        if command:find("screenscraper") then
            log.write("[fetch] Using ScreenScraper API - network delays or rate limits may occur")
        end

        local output = io.popen(command .. stderr_to_stdout)

        if not output then
            log.write("Failed to run Skyscraper")
            channels.SKYSCRAPER_OUTPUT:push({
                data = {},
                error = "Failed to run Skyscraper",
                loading = false
            })
            break
        end

        if input_data.version then -- Special command. Log version only
            local result = output:read("*a")
            pcall(output.close, output)
            output = nil
            local lines = utils.split(result, "\n")
            log_version(lines)
            goto continue
        end

        local parsed = false
        local retriable_error = false
        local line_count = 0

        log.write("[fetch] Reading output from Skyscraper...")

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

            -- WiFi check during scraping (skip in offline mode)
            if not is_offline_mode() and not wifi.is_connected() then
                aborted = true
                log.write("WiFi disconnected during scraping")
                channels.SKYSCRAPER_OUTPUT:push({
                    log = "[fetch] WiFi disconnected. Stopping scrape.",
                    error = "WiFi disconnected",
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
            -- RUNNING TASK; PUSH OUTPUT
            if op == "update" or op == "import" then
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
                log.write(string.format("[fetch] %s", line), "skyscraper")
                channels.SKYSCRAPER_OUTPUT:push({
                    log = string.format("[fetch] %s", line)
                })
                if rtype == "game" then
                    emit_ready(res, current_platform, input_folder, skipped)
                end
            end
            
            if res == nil and (error == nil or error == "") then 
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
                end
                break
            end
        end

        -- Safely close output if still open
        if output then
            pcall(output.close, output)
        end

        -- Log completion details
        log.write(string.format("[fetch] Process ended. Lines received: %d, Aborted: %s, Retriable error: %s",
            line_count, tostring(aborted), tostring(retriable_error)))

        if aborted then
            -- graceful stop
            break
        end

        -- Notify that fetch operation completed for this platform
        if current_platform and not aborted and not retriable_error then
            channels.SKYSCRAPER_OUTPUT:push({
                log = string.format("[fetch] Platform %s completed", current_platform)
            })
        end

        if retriable_error and attempts < max_attempts then
            channels.SKYSCRAPER_OUTPUT:push({
                log = string.format("[fetch] Retrying in %ds (attempt %d/%d)", retry_delay_secs, attempts + 1,
                    max_attempts)
            })
            socket.sleep(retry_delay_secs)
            retry_delay_secs = math.min(15, retry_delay_secs * 2)
            -- retry loop continues
        else
            -- either success or non-retriable error or max attempts exhausted
            break
        end
    end
end

function love.threaderror(thread, errorstr)
    print(errorstr)
    log.write(errorstr)
end
