require("globals")
local log = require("lib.log")

local cache_backup_channel = love.thread.getChannel("cache_backup")
local running = true

while running do
  log.write("Starting Zip to compress and move cache folder")
  local stderr_to_stdout = " 2>&1"
  local command =
  'zip -r /mnt/sdcard/ARCHIVE/scrappy_cache-$(date +"%Y-%m-%d-%H-%M-%S").zip /mnt/mmc/MUOS/application/.scrappy/data/cache/'
  local output = io.popen(command .. stderr_to_stdout)

  if not output then
    log.write("Failed to run Zip")
    cache_backup_channel:push({ data = {}, error = "Failed to run Zip", loading = false })
    running = false
  end

  for line in output:lines() do
    if line:find("adding") then
      cache_backup_channel:push({ command_finished = true })
    elseif line:find("error") then
      cache_backup_channel:push({ data = {}, error = line, loading = false })
    end
  end

  running = false
end
