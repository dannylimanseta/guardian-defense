-- Game.lua - Main game controller
-- Handles initialization, update, and rendering

local ResolutionManager = require 'src/core/ResolutionManager'
local GridMap = require 'src/systems/GridMap'
local Config = require 'src/config/Config'
local Theme = require 'src/theme'
local DeckManager = require 'src/systems/DeckManager'
local HandUI = require 'src/ui/HandUI'
-- local moonshine = require 'src/libs/moonshine'

local Game = {}

function Game:init()
    -- Initialize resolution system first
    ResolutionManager:init()
    
    -- Initialize game systems
    self.gridMap = GridMap:new()
    self.gridMap:init()
    -- Wire hit callback for screen move
    self.gridMap.onHitScreenMove = function(dx, dy)
        self.screenMoveX = (self.screenMoveX or 0) + dx
        self.screenMoveY = (self.screenMoveY or 0) + dy
    end
    
    -- Set up Love2D window
    love.window.setTitle(Config.WINDOW_TITLE)
    love.graphics.setDefaultFilter("nearest", "nearest") -- Pixel perfect scaling
    
    -- Disable post-processing by default
    self.effect = nil
    self.postFXEnabled = false
    
    print("Guardian Defense initialized successfully!")
end

    -- Initialize deck/hand systems
    self.deck = DeckManager:new()
    self.deck:loadOrCreateDeck()
    self.deck:startWave()
    self.handUI = HandUI:new(self.deck)

function Game:update(dt)
    ResolutionManager:update()
    self.gridMap:update(dt)
    -- Decay screen move offsets
    if self.screenMoveX or self.screenMoveY then
        self.screenMoveX = (self.screenMoveX or 0) * math.max(0, 1 - 8 * dt)
        self.screenMoveY = (self.screenMoveY or 0) * math.max(0, 1 - 8 * dt)
        if math.abs(self.screenMoveX) < 0.1 then self.screenMoveX = 0 end
        if math.abs(self.screenMoveY) < 0.1 then self.screenMoveY = 0 end
    end
end

function Game:draw()
    -- Clear screen
    love.graphics.clear(Config.COLORS.BACKGROUND)
    
    -- Render scene to logical canvas first
    ResolutionManager:startDraw()
    self.gridMap:draw()
    -- Hand UI and minimal HUD on top of scene within logical canvas
    if self.handUI then
        self.handUI:draw()
    end
    -- HUD overlay (optional)
    if Config.UI.SHOW_CORE_HEALTH then
        self:drawHUD()
    end
    
    -- Present canvas to screen
    love.graphics.setCanvas()
    love.graphics.push()
    love.graphics.translate(ResolutionManager.offsetX + (self.screenMoveX or 0), ResolutionManager.offsetY + (self.screenMoveY or 0))
    love.graphics.scale(ResolutionManager.scale)
    love.graphics.draw(ResolutionManager.canvas)
    love.graphics.pop()
end

function Game:keypressed(key)
    if key == "escape" then
        love.event.quit()
    elseif key == "f11" or key == "f" then
        -- Toggle fullscreen
        ResolutionManager:toggleFullscreen()
    elseif key == "i" then
        -- Print resolution info
        local info = ResolutionManager:getScaleInfo()
        print(string.format("Resolution Info:"))
        print(string.format("  Screen: %dx%d (%.2f:1)", info.screenWidth, info.screenHeight, info.aspectRatio))
        print(string.format("  Logical: %dx%d (%.2f:1)", info.logicalWidth, info.logicalHeight, info.logicalAspectRatio))
        print(string.format("  Scale: %.2f", info.scale))
        print(string.format("  Draw Area: %dx%d", info.drawWidth, info.drawHeight))
        print(string.format("  Offset: (%d, %d)", info.offsetX, info.offsetY))
    elseif key == "p" then
        -- Toggle post-processing
        self.postFXEnabled = not self.postFXEnabled
        print("PostFX enabled:", self.postFXEnabled)
    end
    
    self.gridMap:keypressed(key)
end

function Game:mousepressed(x, y, button)
    -- Convert screen coordinates to game coordinates
    local gameX, gameY = ResolutionManager:screenToGame(x, y)
    if self.handUI and self.handUI:mousepressed(gameX, gameY, button) then
        return
    end
    self.gridMap:mousepressed(gameX, gameY, button)
end

function Game:mousemoved(x, y, dx, dy)
    local gameX, gameY = ResolutionManager:screenToGame(x, y)
    if self.handUI then
        self.handUI:mousemoved(gameX, gameY, dx, dy)
    end
    self.gridMap:mousemoved(gameX, gameY, dx, dy)
end

function Game:mousereleased(x, y, button)
    local gameX, gameY = ResolutionManager:screenToGame(x, y)
    if not self.handUI then return end
    local info = self.handUI:mousereleased(gameX, gameY, button)
    if not info or not info.cardId or not info.cardIndex then return end
    -- Check energy before attempting to play
    local can, reason = self.deck:canPlayCard(info.cardId)
    if not can then
        if Config.GAME.DEBUG_MODE then
            print('Cannot play card:', reason)
        end
        return
    end
    -- Determine target tile
    local tile = self.gridMap:getTileAtPosition(gameX, gameY)
    if not tile then
        if Config.GAME.DEBUG_MODE then print('Drop not on grid') end
        return
    end
    local def = self.deck:playCardFromHand(info.cardIndex)
    if not def then
        if Config.GAME.DEBUG_MODE then print('Play failed') end
        return
    end
    local placed = false
    if def.type == 'place_tower' and def.payload and def.payload.tower == 'crossbow' then
        placed = self.gridMap:placeTowerAt(tile.x, tile.y)
    end
    if not placed then
        -- refund energy and card if placement invalid
        self.deck:refundLastPlayed(def.id)
        if Config.GAME.DEBUG_MODE then print('Placement invalid, refunded') end
    end
end

function love.resize(width, height)
    -- Handle window resize
    ResolutionManager:resize(width, height)
end

function Game:drawHUD()
    -- Draw a small panel with core health in the top-left of the logical canvas
    local padding = Config.UI.PANEL_PADDING or 8
    local panelWidth = 160
    local panelHeight = 48
    local x = 8
    local y = 8

    Theme.drawPanel(x, y, panelWidth, panelHeight)

    local coreHealth = 0
    if self.gridMap and self.gridMap.enemySpawnManager and self.gridMap.enemySpawnManager.getCoreHealth then
        coreHealth = self.gridMap.enemySpawnManager:getCoreHealth()
    end
    local maxHealth = Config.GAME.CORE_HEALTH
    local text = string.format("Core: %d/%d", coreHealth, maxHealth)
    Theme.drawText(text, x + padding, y + padding, Theme.FONTS.MEDIUM, Theme.COLORS.WHITE)
end

return Game
