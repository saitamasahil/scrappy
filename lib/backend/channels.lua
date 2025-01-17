local channels = {
  LOG_INPUT         = love.thread.getChannel("log"),
  SKYSCRAPER_INPUT  = love.thread.getChannel("skyscraper_command"),
  SKYSCRAPER_OUTPUT = love.thread.getChannel("skyscraper_output"),
  TASK_INPUT        = love.thread.getChannel("task_input"),
  TASK_OUTPUT       = love.thread.getChannel("task_output")
}

return channels
