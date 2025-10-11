-- conf.lua - Love2D Configuration
-- Window and game settings

function love.conf(t)
    t.title = "Guardian Defense"
    t.author = "Your Name"
    t.version = "11.4"
    
    -- Window settings
    t.window.width = 1280
    t.window.height = 720
    t.window.resizable = true
    t.window.minwidth = 640
    t.window.minheight = 480
    t.window.vsync = 1
    t.window.highdpi = true
    t.window.fullscreen = false
    t.window.fullscreentype = "desktop"
    
    -- Disable unused modules for better performance
    t.modules.joystick = false
    t.modules.physics = false
    t.modules.thread = false
    t.modules.touch = false
end
