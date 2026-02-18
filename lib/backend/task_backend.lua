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
    local ts = os.date("%Y-%m-%d-%H-%M-%S")
    local zip_file = string.format("/mnt/sdcard/ARCHIVE/scrappy_cache-%s.zip", ts)
    local mux_file = string.format("/mnt/sdcard/ARCHIVE/scrappy_cache-%s.muxzip", ts)
    
    -- Ensure relative path structure for MuOS Archive Manager (starts with 'application')
    local relative_cache = CACHE_DIR:gsub(STORAGE_ROOT .. "/", ""):gsub("/$", "")
    
    -- cd to STORAGE_ROOT so zip captures 'application/...' structure
    local cmd = string.format('mkdir -p /mnt/sdcard/ARCHIVE && cd "%s" && LD_LIBRARY_PATH= zip -rq "%s" "%s" && mv "%s" "%s"', STORAGE_ROOT, zip_file, relative_cache, zip_file, mux_file)
    base_task_command("backup", cmd)
end

local function backup_cache_sd1()
    log.write("Starting Zip to compress and move cache folder to SD1")
    local ts = os.date("%Y-%m-%d-%H-%M-%S")
    local zip_file = string.format("/mnt/mmc/ARCHIVE/scrappy_cache-%s.zip", ts)
    local mux_file = string.format("/mnt/mmc/ARCHIVE/scrappy_cache-%s.muxzip", ts)
    
    -- Ensure relative path structure for MuOS Archive Manager (starts with 'application')
    local relative_cache = CACHE_DIR:gsub(STORAGE_ROOT .. "/", ""):gsub("/$", "")
    
    -- cd to STORAGE_ROOT so zip captures 'application/...' structure
    local cmd = string.format('mkdir -p /mnt/mmc/ARCHIVE && cd "%s" && LD_LIBRARY_PATH= zip -rq "%s" "%s" && mv "%s" "%s"', STORAGE_ROOT, zip_file, relative_cache, zip_file, mux_file)
    base_task_command("backup_sd1", cmd)
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

    if task == "backup_sd1" then
        backup_cache_sd1()
    end

    if task == "migrate" then
        migrate_cache()
    end

    if task == "update_app" then
        update_app()
    end

    running = false
end
