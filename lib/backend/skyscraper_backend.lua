require("globals")
local parser   = require("lib.parser")
local log      = require("lib.log")
local channels = require("lib.backend.channels")
local pprint   = require("lib.pprint")
local utils    = require("helpers.utils")

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

local function emit_ready(game, platform, skipped)
  print(string.format("Game queued: \"%s\"", game))
  channels.SKYSCRAPER_GAME_QUEUE:push({ game = game, platform = platform, skipped = skipped })
  channels.SKYSCRAPER_OUTPUT:push({ log = string.format("Game queued: \"%s\"", game) })
end

while true do
  ::continue::
  -- Demand a table with command, platform, type, and game from SKYSCRAPER_INPUT
  local input_data = channels.SKYSCRAPER_INPUT:demand()

  -- Extract the command, platform, type, and game
  local command = input_data.command
  local current_platform = input_data.platform
  -- local game = utils.get_filename(input_data.game)
  -- local task_id = input_data.task_id

  log.write("Starting Skyscraper, please wait...")

  if current_platform then
    channels.SKYSCRAPER_OUTPUT:push({ log = "Starting Skyscraper for \"" .. current_platform .. "\", please wait..." })
  end

  local stderr_to_stdout = " 2>&1"
  local output = io.popen(command .. stderr_to_stdout)

  log.write(string.format("Running command: %s", command))
  log.write(string.format("Platform: %s | Game: %s\n", current_platform or "none", "none"))

  if not output then
    log.write("Failed to run Skyscraper")
    channels.SKYSCRAPER_OUTPUT:push({ data = {}, error = "Failed to run Skyscraper", loading = false })
    goto continue
  end

  -- if game and current_platform then
  --   channels.SKYSCRAPER_OUTPUT:push({ data = { title = game, platform = current_platform }, error = nil })
  -- end

  if input_data.version then -- Special command. Log version only
    local result = output:read("*a")
    output:close()
    local lines = utils.split(result, "\n")
    log_version(lines)
    goto continue
  end

  local parsed = false
  for line in output:lines() do
    -- print(line)
    line = utils.strip_ansi_colors(line)
    -- if game ~= "fake-rom" then log.write(line, "skyscraper") end
    local res, error, skipped, rtype = parser.parse(line)
    if res ~= nil or error then parsed = true end
    if res ~= nil then
      log.write(string.format("[gathering] %s", line), "skyscraper")
      -- channels.SKYSCRAPER_OUTPUT:push({ log = string.format("[gathering] %s", line) })
      if rtype == "game" then
        emit_ready(res, current_platform, skipped)
      end
    end
    -- if game ~= nil then
    --   emit_ready(game, current_platform)
    --   pprint({
    --     data = {
    --       -- title = game,
    --       platform = current_platform,
    --     },
    --     -- task_id = task_id,
    --     success = game ~= nil,
    --     error = error,
    --     loading = false
    --   })
    -- channels.SKYSCRAPER_OUTPUT:push({
    --   data = {
    --     title = success,
    --     platform = current_platform,
    --   },
    --   task_id = task_id,
    --   success = success,
    --   error = error,
    --   loading = false
    -- })
    -- end

    -- if error ~= nil and error ~= "" then
    --   log.write("ERROR: " .. error, "skyscraper")
    --   channels.SKYSCRAPER_OUTPUT:push({ data = {}, error = error, loading = false })
    --   break
    -- end
  end

  -- if not parsed then
  --   log.write(string.format("Failed to parse Skyscraper output for %s", game))
  --   channels.SKYSCRAPER_OUTPUT:push({
  --     loading = false,
  --     task_id = task_id,
  --     success = false
  --   })
  -- end

  -- channels.SKYSCRAPER_OUTPUT:push({ command_finished = true })
end

function love.threaderror(thread, errorstr)
  print(errorstr)
  -- channels.SKYSCRAPER_OUTPUT:push({ data = {}, error = errorstr, loading = false })
  log.write(errorstr)
end
