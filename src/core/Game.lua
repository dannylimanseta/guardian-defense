-- Game.lua - Main game controller
-- Handles initialization, update, and rendering

local ResolutionManager = require 'src/core/ResolutionManager'
local GridMap = require 'src/systems/GridMap'
local Config = require 'src/config/Config'
local Theme = require 'src/theme'
local DeckManager = require 'src/systems/DeckManager'
local HandUI = require 'src/ui/HandUI'
-- local moonshine = require 'src/libs/moonshine'
local WaveManager = require 'src/systems/WaveManager'

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
    -- Use nearest for sprites/canvas, but fonts are set to linear individually
    love.graphics.setDefaultFilter("nearest", "nearest")
    
    -- Disable post-processing by default
    self.effect = nil
    self.postFXEnabled = false
    
    -- Initialize deck/hand systems
    self.deck = DeckManager:new()
    self.deck:loadOrCreateDeck()
    self.deck:startWave()
    self.handUI = HandUI:new(self.deck)

    -- Initialize wave manager with current stage and spawn system
    self.waveManager = WaveManager:new('level_1', self.gridMap.enemySpawnManager)
end

function Game:update(dt)
    ResolutionManager:update()
    self.gridMap:update(dt)
    if self.handUI and self.handUI.update then
        self.handUI:update(dt)
    end
    -- Update waves
    if self.waveManager and self.waveManager.update then
        self.waveManager:update(dt)
    end
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
    -- Apply screen shake inside the canvas so the canvas stays aligned with letterbox
    love.graphics.push()
    love.graphics.translate(self.screenMoveX or 0, self.screenMoveY or 0)
    self.gridMap:draw()
    love.graphics.pop()
    -- Stop drawing to the world canvas
    love.graphics.setCanvas()
    
    -- Present canvas to screen
    -- Present world canvas with screen shake
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.push()
    love.graphics.translate(ResolutionManager.offsetX, ResolutionManager.offsetY)
    love.graphics.scale(ResolutionManager.scale)
    love.graphics.draw(ResolutionManager.canvas)
    love.graphics.pop()
    
    -- Draw HUD/UI above the game (no shake), but scaled to logical resolution
    love.graphics.push()
    love.graphics.translate(ResolutionManager.offsetX, ResolutionManager.offsetY)
    love.graphics.scale(ResolutionManager.scale)
    if self.handUI then
        self.handUI:draw()
    end
    if Config.UI.SHOW_CORE_HEALTH then
        self:drawHUD()
    end
    if self.gridMap and self.gridMap.drawInfoPanel then
        self.gridMap:drawInfoPanel()
    end
    love.graphics.pop()
end

function Game:keypressed(key)
    if key == "escape" then
        love.event.quit()
    elseif key == "f11" or key == "f" then
        -- Toggle fullscreen
        ResolutionManager:toggleFullscreen()
    elseif key == "p" then
        -- Toggle post-processing
        self.postFXEnabled = not self.postFXEnabled
    elseif key == "space" then
        -- Start next wave (supports overlap)
        if self.waveManager and self.waveManager.startNextWave then
            self.waveManager:startNextWave()
        end
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
    local handled = false
    if self.handUI then
        handled = self.handUI:mousemoved(gameX, gameY, dx, dy) or false
    end
    -- While dragging a card, restrict hover to eligible tiles
    if self.handUI and self.handUI.drag and self.handUI.drag.active then
        local tile = self.gridMap:getTileAtPosition(gameX, gameY)
        local eligible = false
        if tile then
            -- For now, only crossbow tower placement is supported
            -- Eligibility: must be build spot and not occupied
            eligible = self.gridMap:isBuildSpot(tile.x, tile.y) and (not self.gridMap:isOccupied(tile.x, tile.y))
        end
        self.gridMap:setHoverFromPlacement(tile, eligible)
    else
        -- Re-enable general hover computation for towers/tiles, but keep hover rect hidden
        self.gridMap:mousemoved(gameX, gameY, dx, dy)
        self.gridMap.showHoverRect = false
    end
end

function Game:mousereleased(x, y, button)
    local gameX, gameY = ResolutionManager:screenToGame(x, y)
    if not self.handUI then return end
    local info = self.handUI:mousereleased(gameX, gameY, button)
    if not info or not info.cardId or not info.cardIndex then return end
    -- Check energy before attempting to play
    local can, reason = self.deck:canPlayCard(info.cardId)
    if not can then return end
    -- Determine target tile
    local tile = self.gridMap:getTileAtPosition(gameX, gameY)
    if not tile then return end
    local def = self.deck:playCardFromHand(info.cardIndex)
    if not def then return end
    local placed = false
    if def.type == 'place_tower' and def.payload and def.payload.tower == 'crossbow' then
        placed = self.gridMap:placeTowerAt(tile.x, tile.y, def.payload.tower, def.payload.level or 1)
    end
    if not placed then
        -- refund energy and card if placement invalid
        self.deck:refundLastPlayed(def.id)
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
