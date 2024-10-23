_G.nativefs = require("lib.nativefs")
_G.timer = require("lib.timer")
_G.WORK_DIR = nativefs.getWorkingDirectory()

_G.INPUT_CHANNEL = love.thread.getChannel("skyscraper-command")
_G.OUTPUT_CHANNEL = love.thread.getChannel("skyscraper-output")

_G.SKYSCRAPER_ERRORS = {
  "doesn't exist or can't be accessed by current user. Please check path and permissions.",
  "ScreenScraper APIv2 returned invalid / empty Json.",
  "No such file or directory",
  "cannot execute binary file: Exec format error",
}
