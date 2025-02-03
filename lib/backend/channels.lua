local channels = {
  LOG_INPUT         = love.thread.getChannel("log"),
  SKYSCRAPER_INPUT  = love.thread.getChannel("skyscraper_command"),
  SKYSCRAPER_OUTPUT = love.thread.getChannel("skyscraper_output"),
  TASK_OUTPUT       = love.thread.getChannel("task_output"),
  WATCHER_INPUT     = love.thread.getChannel("watcher_input"),
  WATCHER_OUTPUT    = love.thread.getChannel("watcher_output"),
}

return channels
