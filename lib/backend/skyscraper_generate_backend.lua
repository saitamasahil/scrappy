require("globals")
local socket   = require("socket")
local parser   = require("lib.parser")
local log      = require("lib.log")
local channels = require("lib.backend.channels")
local utils    = require("helpers.utils")
local pprint   = require("lib.pprint")

-- local input_data = ...
-- local running  = true

while true do
  ::continue::
  -- Demand a table with command, platform, type, and game from SKYSCRAPER_INPUT
  local input_data = channels.SKYSCRAPER_GEN_INPUT:demand()

  print("\nSkyscraper received input data:")
  pprint(input_data)
  print("\n")

  -- Extract the command, platform, type, and game
  local command = input_data.command
  local current_platform = input_data.platform
  local game = utils.get_filename(input_data.game)

  channels.SKYSCRAPER_OUTPUT:push({ log = string.format("[gen] Queued \"%s\"", game) })

  local stderr_to_stdout = " 2>&1"
  local output = io.popen(command .. stderr_to_stdout)

  log.write(string.format("Running generate command: %s", command))
  log.write(string.format("Platform: %s | Game: %s\n", current_platform or "none", game or "none"))

  print(string.format("Running generate command: %s", command))
  -- print(string.format("Platform: %s | Game: %s\n", current_platform or "none", game or "none"))

  if not output then
    log.write("Failed to run Skyscraper")
    channels.SKYSCRAPER_OUTPUT:push({ error = "Failed to run Skyscraper" })
    goto continue
  end

  -- if game and current_platform then
  --   channels.SKYSCRAPER_OUTPUT:push({ data = { title = game, platform = current_platform }, error = nil })
  -- end

  local parsed = false
  local sent_title = false
  local had_error = false
  for line in output:lines() do
    line = utils.strip_ansi_colors(line)
    if game ~= "fake-rom" then log.write(line, "skyscraper") end
    local res, error, skipped, rtype = parser.parse(line)
    if res ~= nil or error then parsed = true end
    if res ~= nil and rtype == "game" then
      pprint({
        title = res,
        platform = current_platform,
        success = not skipped,
        error = error,
      })
      channels.SKYSCRAPER_OUTPUT:push({
        title = res,
        platform = current_platform,
        success = not skipped,
        error = error,
      })
      sent_title = true
    end

    if error ~= nil and error ~= "" then
      log.write("ERROR: " .. error, "skyscraper")
      channels.SKYSCRAPER_OUTPUT:push({ error = error })
      had_error = true
      break
    end
  end

  -- Always emit a final result if no title was sent during parsing
  if not sent_title then
    if not parsed then
      log.write(string.format("Failed to parse Skyscraper output for %s", game))
    end
    channels.SKYSCRAPER_OUTPUT:push({
      title = game,
      platform = current_platform,
      error = (not parsed) and "Failed to parse Skyscraper output" or nil,
      success = not had_error
    })
  end

  -- channels.SKYSCRAPER_OUTPUT:push({ command_finished = true })

  channels.SKYSCRAPER_OUTPUT:push({ log = string.format("[gen] Finished \"%s\"", game) })
  channels.SKYSCRAPER_GEN_OUTPUT:push({ finished = true })
end

function love.threaderror(thread, errorstr)
  print(errorstr)
  channels.SKYSCRAPER_OUTPUT:push({ error = errorstr })
  log.write(errorstr)
end
