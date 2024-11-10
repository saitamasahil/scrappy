function love.conf(t)
  t.version = "11.4"
  t.console = false

  t.window.title = "Scrappy"
  t.window.icon = nil
  t.window.width = 640
  t.window.height = 480
  t.window.borderless = false
  t.window.resizable = false
  t.window.vsync = 1
  t.window.display = 1
  t.window.highdpi = false
  t.window.x = nil
  t.window.y = nil

  t.modules.thread = true
  t.modules.audio = false
  t.modules.mouse = false
  t.modules.physics = false
  t.modules.sound = false
  t.modules.touch = false
  t.modules.video = false
end
