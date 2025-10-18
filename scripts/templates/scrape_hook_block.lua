  -- TEMP behavior: run Skyscraper --help and save output to logs, then stop
  local function run_help_and_log_once()
    if not nativefs.getInfo("logs") then nativefs.createDirectory("logs") end
    local ts = os.date("%Y%m%d_%H%M%S")
    local help_log = string.format("logs/skyscraper-help-%s.log", ts)
    local cmd = string.format("%s --help", skyscraper.base_command)
    log.write(string.format("[help] Executing: %s", cmd))
    local handle = io.popen(cmd .. " 2>&1", "r")
    if not handle then
      log.write("[help] Failed to execute Skyscraper --help")
      nativefs.write(help_log, "Failed to execute Skyscraper --help\n")
      show_info_window("Help captured", "Failed to run Skyscraper. See " .. help_log)
      channels.SKYSCRAPER_OUTPUT:push({ log = "[help] Failed to execute Skyscraper --help" })
      return
    end
    local out = handle:read("*a") or ""
    handle:close()
    nativefs.write(help_log, out)
    if out ~= "" then
      for line in out:gmatch("([^\n]*)\n?") do
        if line ~= "" then channels.SKYSCRAPER_OUTPUT:push({ log = "[help] " .. line }) end
      end
    end
    show_info_window("Help captured", "Skyscraper --help output written to " .. help_log)
  end

  do
    run_help_and_log_once()
    return
  end
