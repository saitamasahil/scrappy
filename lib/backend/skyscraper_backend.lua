require("globals")
local parser   = require("lib.parser")
local log      = require("lib.log")
local channels = require("lib.backend.channels")
local pprint   = require("lib.pprint")
local utils    = require("helpers.utils")
local wifi     = require("helpers.wifi")
local socket   = require("socket")

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
  channels.SKYSCRAPER_GAME_QUEUE:push({ game = game, platform = platform, input_folder = input_folder, skipped = skipped })
end

while true do
  ::continue::
  -- Demand a table with command, platform, type, and game from SKYSCRAPER_INPUT
  local input_data = channels.SKYSCRAPER_INPUT:demand()

  -- Extract the command, platform, type, and game
  local command = input_data.command
  local current_platform = input_data.platform
  local input_folder = input_data.input_folder
  local op = input_data.op

  log.write("Starting Skyscraper, please wait...")

  -- Check WiFi before starting command
  if not wifi.is_connected() then
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
      channels.SKYSCRAPER_OUTPUT:push({ data = {}, error = "Failed to run Skyscraper", loading = false })
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
    local last_output_time = socket.gettime()
    local last_log_time = socket.gettime()
    local no_output_timeout = 600 -- Start with 10 min timeout for initialization/connection
    local scraping_started = false
    local line_count = 0
    
    log.write(string.format("[fetch] Reading output from Skyscraper (init timeout: %ds)", no_output_timeout))
    
    for line in output:lines() do
      line_count = line_count + 1
      local current_time = socket.gettime()
      
      -- Calculate time since last output BEFORE checking abort/timeout
      local elapsed_since_output = current_time - last_output_time
      
      -- Check for scraping start to reduce timeout
      if not scraping_started and (line:find("Fetching limits") or line:find("Starting scraping run") or line:find("Game '")) then
        scraping_started = true
        no_output_timeout = 120 -- Reduce to 120s once scraping begins
        log.write(string.format("[fetch] Scraping started, reducing timeout to %ds", no_output_timeout))
      end
      
      -- Abort check every line
      local abort_sig = channels.SKYSCRAPER_ABORT:pop()
      if abort_sig and abort_sig.abort then
        aborted = true
        log.write("[fetch] Abort signal received, killing process")
        channels.SKYSCRAPER_OUTPUT:push({ log = "[fetch] Aborted by user" })
        if output then
          pcall(output.close, output)
          output = nil
        end
        os.execute("killall -9 Skyscraper Skyscraper.aarch64 2>/dev/null")
        break
      end
      
      -- WiFi check during scraping
      if not wifi.is_connected() then
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

      -- Check if process is hung (no output for extended period)
      if elapsed_since_output > no_output_timeout then
        log.write(string.format("[fetch] No output for %ds, process appears hung (line #%d: '%s')", 
          math.floor(elapsed_since_output), line_count, line:sub(1, 80)))
        channels.SKYSCRAPER_OUTPUT:push({ log = string.format("[fetch] Timeout after %ds - killing process", math.floor(elapsed_since_output)) })
        if output then
          pcall(output.close, output)
          output = nil
        end
        os.execute("killall -9 Skyscraper Skyscraper.aarch64 2>/dev/null")
        aborted = true
        break
      end
      
      -- Update last output time since we got a line
      last_output_time = current_time
      

      
      -- Log long delays between lines (internal log only; keep UI quiet)
      if elapsed_since_output > 15 then
        log.write(string.format("[fetch] Long delay: %ds since last output (line #%d)", math.floor(elapsed_since_output), line_count))
      end
      
      -- Update last output time since we got a line
      last_output_time = current_time

      line = utils.strip_ansi_colors(line)
      -- RUNNING TASK; PUSH OUTPUT
      if op == "update" or op == "import" then
        channels.TASK_OUTPUT:push({ output = line, error = nil })
      end
      local res, error, skipped, rtype = parser.parse(line)
      if res ~= nil or error then parsed = true end
      if res ~= nil then
        log.write(string.format("[fetch] %s", line), "skyscraper")
        channels.SKYSCRAPER_OUTPUT:push({ log = string.format("[fetch] %s", line) })
        if rtype == "game" then
          emit_ready(res, current_platform, input_folder, skipped)
        end
      end

      if error ~= nil and error ~= "" then
        log.write("ERROR: " .. error, "skyscraper")
        channels.SKYSCRAPER_OUTPUT:push({ data = {}, error = error, loading = false })
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
    local total_time = socket.gettime() - last_output_time
    log.write(string.format("[fetch] Process ended. Lines received: %d, Aborted: %s, Retriable error: %s, Total time: %.2fs", 
      line_count, tostring(aborted), tostring(retriable_error), total_time))

    if aborted then
      -- graceful stop
      break
    end
    
    -- Notify that fetch operation completed for this platform
    if current_platform and not aborted and not retriable_error then
      channels.SKYSCRAPER_OUTPUT:push({ log = string.format("[fetch] Platform %s completed", current_platform) })
    end
    
    if retriable_error and attempts < max_attempts then
      channels.SKYSCRAPER_OUTPUT:push({ log = string.format("[fetch] Retrying in %ds (attempt %d/%d)", retry_delay_secs, attempts + 1, max_attempts) })
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
