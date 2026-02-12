require("globals")
local socket = require("socket")
local parser = require("lib.parser")
local log = require("lib.log")
local channels = require("lib.backend.channels")
local utils = require("helpers.utils")
local pprint = require("lib.pprint")

-- local input_data = ...
-- local running  = true

while true do
    ::continue::
    -- Demand a table with command, platform, type, and game from SKYSCRAPER_INPUT
    local input_data = channels.SKYSCRAPER_GEN_INPUT:demand()

    -- Check for exit signal to terminate thread gracefully
    if input_data.exit then
        log.write("[gen] Exit signal received, terminating thread")
        break
    end

    print("\nSkyscraper received input data:")
    pprint(input_data)
    print("\n")

    -- Extract the command, platform, type, and game
    local command = input_data.command
    local current_platform = input_data.platform
    local game = utils.get_filename(input_data.game)
    local original_game = input_data.game -- Keep original for rename tracking
    local input_folder = input_data.input_folder -- Needed for rename

    channels.SKYSCRAPER_OUTPUT:push({
        log = string.format("[gen] Queued \"%s\"", game)
    })

    local stderr_to_stdout = " 2>&1"
    local output = io.popen(command .. stderr_to_stdout)

    log.write(string.format("Running generate command: %s", command))
    log.write(string.format("Platform: %s | Game: %s\n", current_platform or "none", game or "none"))

    print(string.format("Running generate command: %s", command))
    -- print(string.format("Platform: %s | Game: %s\n", current_platform or "none", game or "none"))

    if not output then
        log.write("Failed to run Skyscraper")
        channels.SKYSCRAPER_OUTPUT:push({
            error = "Failed to run Skyscraper"
        })
        channels.SKYSCRAPER_GEN_OUTPUT:push({
            finished = true,
            game = game,
            platform = current_platform
        })
        goto continue
    end

    -- if game and current_platform then
    --   channels.SKYSCRAPER_OUTPUT:push({ data = { title = game, platform = current_platform }, error = nil })
    -- end

    local parsed = false
    local sent_title = false
    local had_error = false
    local aborted = false
    local last_output_time = socket.gettime()

    for line in output:lines() do
        local current_time = socket.gettime()

        -- Abort check
        local abort_sig = channels.SKYSCRAPER_ABORT:pop()
        if abort_sig and (abort_sig == true or abort_sig.abort) then
            aborted = true
            log.write(string.format("[gen] Abort signal received for %s, killing process", game))
            channels.SKYSCRAPER_OUTPUT:push({
                log = string.format("[gen] Aborted \"%s\"", game)
            })
            if output then
                output:close()
            end
            -- Kill any Skyscraper processes
            os.execute("killall -9 Skyscraper Skyscraper.aarch64 2>/dev/null")
            channels.SKYSCRAPER_GEN_OUTPUT:push({
                finished = true,
                game = game,
                platform = current_platform
            })
            goto continue
        end

        -- Update last output time since we got a line
        last_output_time = current_time
        line = utils.strip_ansi_colors(line)
        if game ~= "fake-rom" then
            log.write(line, "skyscraper")
        end
        local res, error, skipped, rtype = parser.parse(line)
        if res ~= nil or error then
            parsed = true
        end
        if res ~= nil and rtype == "game" then
            pprint({
                title = res,
                platform = current_platform,
                success = not skipped,
                error = error,
                original_filename = game,
                input_folder = input_folder
            })
            channels.SKYSCRAPER_OUTPUT:push({
                title = res,
                platform = current_platform,
                success = not skipped,
                error = error,
                original_filename = game,
                input_folder = input_folder
            })
            sent_title = true
        end

        if error ~= nil and error ~= "" then
            log.write("ERROR: " .. error, "skyscraper")
            -- IMPORTANT: Include title so state.tasks gets decremented in main.lua
            channels.SKYSCRAPER_OUTPUT:push({
                title = game,
                platform = current_platform,
                success = false,
                error = error,
                original_filename = game,
                input_folder = input_folder
            })
            had_error = true
            if output then
                output:close()
            end
            channels.SKYSCRAPER_GEN_OUTPUT:push({
                finished = true,
                game = original_game,
                platform = current_platform
            })
            goto continue
        end
    end
    if output then
        output:close()
    end

    -- Always emit a final result if no title was sent during parsing
    if not sent_title then
        if not parsed then
            log.write(string.format("Failed to parse Skyscraper output for %s", game))
        end
        channels.SKYSCRAPER_OUTPUT:push({
            title = game,
            platform = current_platform,
            error = aborted and "Operation aborted" or ((not parsed) and "Failed to parse Skyscraper output" or nil),
            success = (not had_error) and (not aborted),
            original_filename = game,
            input_folder = input_folder
        })
    end

    -- channels.SKYSCRAPER_OUTPUT:push({ command_finished = true })

    channels.SKYSCRAPER_OUTPUT:push({
        log = string.format("[gen] Finished \"%s\"", game)
    })
    channels.SKYSCRAPER_GEN_OUTPUT:push({
        finished = true,
        game = original_game,
        platform = current_platform
    })
end

function love.threaderror(thread, errorstr)
    print(errorstr)
    channels.SKYSCRAPER_OUTPUT:push({
        error = errorstr
    })
    log.write(errorstr)
end
