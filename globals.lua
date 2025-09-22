_G.nativefs = require("lib.nativefs")
_G.timer = require("lib.timer")
_G.WORK_DIR = nativefs.getWorkingDirectory()

local sem_ver = {
  major = 3,
  minor = 0,
  patch = 4,
  extra = ""
}

_G.version = (function()
  local version = string.format("v%d.%d.%d", sem_ver.major, sem_ver.minor, sem_ver.patch)
  if sem_ver.extra ~= "" then
    version = version .. "-" .. sem_ver.extra
  end
  return version
end)()

_G.resolution = "640x480"

_G.device_resolutions = {
  "640x480",
  "720x480",
  "720x720",
  "1024x768",
  "1280x720",
}

_G.SKYSCRAPER_ERRORS = {
  "doesn't exist or can't be accessed by current user. Please check path and permissions.",
  "ScreenScraper APIv2 returned invalid / empty Json.",
  "No such file or directory",
  "cannot execute binary file: Exec format error",
  "Couldn't read artwork xml file",
  "requested either on command line or with",
  "Couldn't create cache folders, please check folder permissions and try again...",
  "Please set a valid platform with",
  "No files to process in cache",
  "Skyscraper came to an untimely end."
}
