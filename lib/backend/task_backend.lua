require("globals")
-- local pprint   = require("lib.pprint")
local log      = require("lib.log")
local channels = require("lib.backend.channels")

local task     = ...
local running  = true

local function base_task_command(id, command)
  local stdout_null = " > /dev/null 2>&1"
  local read_output = "; echo $?" -- 'echo $?' returns 0 if successful
  local handle = io.popen(command .. stdout_null .. read_output)

  if not handle then
    log.write(string.format("Failed to run %s - '%s'", id, command))
    channels.TASK_OUTPUT:push({ data = {}, error = string.format("Failed to run %s", id) })
    return
  end

  local output = handle:read("*a")
  output = output:gsub("\n", "")
  handle:close()

  if output == "0" then
    channels.TASK_OUTPUT:push({ command_finished = true, command = id })
  else
    channels.TASK_OUTPUT:push({ data = {}, error = string.format("Failed to run %s", id) })
    log.write(string.format("Failed to run %s - '%s'", id, command, output))
  end
end

local function migrate_cache()
  log.write("Migrating cache to SD2")
  base_task_command(
    "migrate",
    "cp -r /mnt/mmc/MUOS/application/.scrappy/data/cache/ /mnt/sdcard/scrappy_cache/"
  )
end

local function backup_cache()
  log.write("Starting Zip to compress and move cache folder")
  base_task_command(
    "backup",
    'zip -r /mnt/sdcard/ARCHIVE/scrappy_cache-$(date +"%Y-%m-%d-%H-%M-%S").zip /mnt/mmc/MUOS/application/.scrappy/data/cache/'
  )
end

local function update_app()
  log.write("Updating app")
  base_task_command(
    "update_app",
    "sh scripts/update.sh"
  )
end

while running do
  if task == "backup" then
    backup_cache()
  end

  if task == "migrate" then
    migrate_cache()
  end

  if task == "update_app" then
    update_app()
  end

  running = false
end
