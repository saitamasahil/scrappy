require("globals")
local log                 = require("lib.log")

local task_input_channel  = love.thread.getChannel("task_input")
local task_output_channel = love.thread.getChannel("task_output")
local running             = true

local function migrate_cache()
  log.write("Migrating cache to SD2")
  local stderr_to_stdout = " 2>&1"
  local command =
  'cp -r /mnt/mmc/MUOS/application/.scrappy/data/cache/ /mnt/sdcard/scrappy_cache/; echo $?'
  -- 'echo $?' returns 0 if successful
  local output = io.popen(command .. stderr_to_stdout)

  if not output then
    log.write("Failed to run migrate cache")
    task_output_channel:push({ data = {}, error = "Failed to migrate cache" })
    return
  end

  for line in output:lines() do
    if line:find("0") then
      task_output_channel:push({ command_finished = true, command = "migrate" })
    elseif line:find("cannot stat") then
      task_output_channel:push({ data = {}, error = line })
    end
  end
end

local function backup_cache()
  log.write("Starting Zip to compress and move cache folder")
  local stderr_to_stdout = " 2>&1"
  local command =
  'zip -r /mnt/sdcard/ARCHIVE/scrappy_cache-$(date +"%Y-%m-%d-%H-%M-%S").zip /mnt/mmc/MUOS/application/.scrappy/data/cache/'
  local output = io.popen(command .. stderr_to_stdout)

  if not output then
    log.write("Failed to run Zip")
    task_output_channel:push({ data = {}, error = "Failed to run Zip" })
    return
  end

  for line in output:lines() do
    if line:find("adding") then
      task_output_channel:push({ command_finished = true, command = "backup" })
    elseif line:find("error") then
      task_output_channel:push({ data = {}, error = line })
    end
  end
end

while running do
  local input = task_input_channel:demand()

  if input.command == "backup" then
    backup_cache()
  end

  if input.command == "migrate" then
    migrate_cache()
  end

  running = false
end
