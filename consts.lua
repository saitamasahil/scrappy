_G.nativefs = require("lib.nativefs")
_G.WORK_DIR = nativefs.getWorkingDirectory()

_G.INPUT_CHANNEL = love.thread.getChannel("skyscraper-command")
_G.OUTPUT_CHANNEL = love.thread.getChannel("skyscraper-output")
