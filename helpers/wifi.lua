-- WiFi status helper module
local wifi = {}

-- Network interface to check (standard Linux WiFi interface)
local WIFI_INTERFACE = "wlan0"

-- Check if WiFi is connected by reading operstate
-- Returns true if connected, false otherwise
function wifi.is_connected()
  -- Try operstate first (more reliable)
  local operstate_path = string.format("/sys/class/net/%s/operstate", WIFI_INTERFACE)
  local f = io.open(operstate_path, "r")
  if f then
    local state = f:read("*l")
    f:close()
    if state and state:lower() == "up" then
      return true
    end
  end
  
  -- Fallback to carrier check
  local carrier_path = string.format("/sys/class/net/%s/carrier", WIFI_INTERFACE)
  f = io.open(carrier_path, "r")
  if f then
    local carrier = f:read("*l")
    f:close()
    if carrier and carrier == "1" then
      return true
    end
  end
  
  return false
end

-- Get WiFi status message for display
function wifi.get_status_message()
  if wifi.is_connected() then
    return "WiFi connected"
  else
    return "WiFi not connected. Please connect to WiFi and try again."
  end
end

return wifi
