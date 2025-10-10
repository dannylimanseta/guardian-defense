-- Guardian Defense - Main Entry Point
-- Love2D Game with Grid Map System

local Game = require 'src/core/Game'

function love.load()
    Game:init()
end

function love.update(dt)
    Game:update(dt)
end

function love.draw()
    Game:draw()
end

function love.keypressed(key)
    Game:keypressed(key)
end

function love.mousepressed(x, y, button)
    Game:mousepressed(x, y, button)
end

function love.mousemoved(x, y, dx, dy)
    Game:mousemoved(x, y, dx, dy)
end

function love.mousereleased(x, y, button)
    if Game.mousereleased then
        Game:mousereleased(x, y, button)
    end
end
