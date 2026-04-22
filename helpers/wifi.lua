-- Network status helper module
local wifi = {}

-- Network interfaces to check (standard Linux WiFi and Ethernet interfaces)
local INTERFACES = {"wlan0", "eth0", "wlan1", "eth1"}

-- Check if network is connected by reading operstate
-- Returns true if connected, false otherwise
function wifi.is_connected()
    for _, iface in ipairs(INTERFACES) do
        -- Try operstate first (more reliable)
        local operstate_path = string.format("/sys/class/net/%s/operstate", iface)
        local f = io.open(operstate_path, "r")
        if f then
            local state = f:read("*l")
            f:close()
            if state and state:lower() == "up" then
                return true
            end
        end

        -- Fallback to carrier check
        local carrier_path = string.format("/sys/class/net/%s/carrier", iface)
        f = io.open(carrier_path, "r")
        if f then
            local carrier = f:read("*l")
            f:close()
            if carrier and carrier == "1" then
                return true
            end
        end
    end

    return false
end

-- Get network status message for display
function wifi.get_status_message()
    if wifi.is_connected() then
        return "Network connected"
    else
        return "Network not connected. Please connect to a network and try again."
    end
end

return wifi
