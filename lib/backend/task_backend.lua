require("globals")
-- local pprint   = require("lib.pprint")
local log = require("lib.log")
local channels = require("lib.backend.channels")

local task = ...
local running = true

-- Newer muOS storage root
local STORAGE_ROOT = "/run/muos/storage"
local APP_ROOT = STORAGE_ROOT .. "/application/Scrappy/.scrappy"
local CACHE_DIR = APP_ROOT .. "/data/cache/"

local function base_task_command(id, command)
    local stderr_to_stdout = " 2>&1"
    -- local stdout_null = " > /dev/null 2>&1"
    -- local read_output = "; echo $?" -- 'echo $?' returns 0 if successful
    local handle = io.popen(command .. stderr_to_stdout)

    if not handle then
        log.write(string.format("Failed to run %s - '%s'", id, command))
        channels.TASK_OUTPUT:push({
            output = "Command failed",
            error = string.format("Failed to run %s", id)
        })
        return
    end

    for line in handle:lines() do
        channels.TASK_OUTPUT:push({
            output = line,
            error = nil
        })
    end

    channels.TASK_OUTPUT:push({
        command_finished = true,
        command = id
    })
    log.write(string.format("Finished command %s", id, command))
end

local function migrate_cache()
    log.write("Migrating cache to SD2")
    base_task_command("migrate", string.format("LD_LIBRARY_PATH= cp -r \"%s\" /mnt/sdcard/scrappy_cache/", CACHE_DIR))
end

local function backup_cache()
    log.write("Starting Zip to compress and move cache folder")
    base_task_command("backup", string.format(
        'LD_LIBRARY_PATH= zip -rq /mnt/sdcard/ARCHIVE/scrappy_cache-$(date +"%%Y-%%m-%%d-%%H-%%M-%%S").zip "%s"', CACHE_DIR))
end

local function update_app()
    -- IMPORTANT: Unset LD_LIBRARY_PATH so curl/wget use system libraries
    -- instead of Scrappy's bundled LÖVE libraries from bin/libs
    local cmd = string.format("cd \"%s\" && LD_LIBRARY_PATH= sh scripts/update.sh", APP_ROOT)
    log.write("Updating app with command: " .. cmd)
    base_task_command("update_app", cmd)
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
