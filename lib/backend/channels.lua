local channels = {
  LOG_INPUT             = love.thread.getChannel("log"),
  SKYSCRAPER_INPUT      = love.thread.getChannel("skyscraper_input"),
  SKYSCRAPER_OUTPUT     = love.thread.getChannel("skyscraper_output"),
  SKYSCRAPER_GEN_INPUT  = love.thread.getChannel("skyscraper_generate_input"),
  SKYSCRAPER_GAME_QUEUE = love.thread.getChannel("skyscraper_midleware"),
  SKYSCRAPER_GEN_OUTPUT = love.thread.getChannel("skyscraper_generate_output"),
  TASK_OUTPUT           = love.thread.getChannel("task_output"),
  SKYSCRAPER_ABORT      = love.thread.getChannel("skyscraper_abort"),
}

return channels
