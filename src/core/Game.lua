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
local EventBus = require 'src/core/EventBus'

local Game = {}

function Game:init()
    -- Initialize resolution system first
    ResolutionManager:init()
    
    -- Initialize game systems
    self.bus = EventBus:new()
    self.gridMap = GridMap:new()
    self.gridMap:init()
    -- Provide event bus to grid map and downstream systems
    self.gridMap.eventBus = self.bus
    -- Subscribe to enemy kill events for coin handling
    if self.bus and self.bus.on then
        self.unsubscribeEnemyKilled = self.bus:on('enemy_killed', function(enemyId, worldX, worldY)
            self:handleEnemyKilled(enemyId, worldX, worldY)
        end)
    end
    if self.gridMap and self.gridMap.setTowerUpgradeRequest then
        self.gridMap:setTowerUpgradeRequest(function(tower, targetLevel, cost)
            self:attemptTowerUpgrade(tower, targetLevel, cost)
        end)
    end
    if self.gridMap and self.gridMap.setTowerDestroyRequest then
        self.gridMap:setTowerDestroyRequest(function(tower)
            self:attemptTowerDestroy(tower)
        end)
    end
    -- Wire hit callback for screen move
    self.gridMap.onHitScreenMove = function(dx, dy)
        self.screenMoveX = (self.screenMoveX or 0) + dx
        self.screenMoveY = (self.screenMoveY or 0) + dy
    end
    
    -- Set up Love2D window
    love.window.setTitle(Config.WINDOW_TITLE)
    -- Use linear filtering globally; override per asset if pixel-crisp visuals are needed
    love.graphics.setDefaultFilter("linear", "linear")
    
    -- Disable post-processing by default
    self.effect = nil
    self.postFXEnabled = false
    
    -- HUD assets
    self.coinIcon = nil
    self.coinCount = 0
    self.coinPickups = {}

    -- Initialize deck/hand systems
    self.deck = DeckManager:new()
    self.deck:loadOrCreateDeck()
    self.deck:startRun()
    self.handUI = HandUI:new(self.deck)

    -- Initialize wave manager with current stage, spawn system, and deck manager (for intermission hooks)
    self.waveManager = WaveManager:new('level_1', self.gridMap.enemySpawnManager, self.deck)
    -- Provide GridMap to WaveManager for path-effect clearing hooks
    if self.waveManager then
        self.waveManager.gridMap = self.gridMap
    end
end

function Game:update(dt)
    ResolutionManager:update()
    self.gridMap:update(dt)
    self:updateCoinPickups(dt)
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
    self:drawCoinTracker()
    if self.gridMap and self.gridMap.drawUpgradeMenu then
        local costCheck = function(cost)
            return (self.coinCount or 0) >= (cost or 0)
        end
        self.gridMap:drawUpgradeMenu(costCheck)
    end
    if self.gridMap and self.gridMap.drawInfoPanel then
        self.gridMap:drawInfoPanel()
    end
    self:drawCoinPickups()

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
        local cardDef = nil
        if self.handUI.drag.cardId then
            cardDef = self.deck:getCardDef(self.handUI.drag.cardId)
        end
        if tile then
            if cardDef and cardDef.type == 'modify_tower' then
                eligible = self.gridMap:isOccupied(tile.x, tile.y)
            elseif cardDef and cardDef.type == 'apply_path_effect' then
                eligible = self.gridMap:isPathTile(tile.x, tile.y) and (not self.gridMap:hasPathEffect(tile.x, tile.y))
            elseif cardDef and cardDef.type == 'apply_tower_buff' then
                eligible = self.gridMap:isOccupied(tile.x, tile.y)
            else
                -- Eligibility: must be build spot and not occupied
                eligible = self.gridMap:isBuildSpot(tile.x, tile.y) and (not self.gridMap:isOccupied(tile.x, tile.y))
            end
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
    local startX, startY = info.startX, info.startY
    -- Check energy before attempting to play
    local can, reason = self.deck:canPlayCard(info.cardId)
    if not can then return end
    -- Determine card definition and play it (energy deducted here)
    local def = self.deck:playCardFromHand(info.cardIndex)
    if not def then return end
    local placed = false
    local requiresTarget = (def.requiresTarget ~= false)
    if requiresTarget then
        local tile = self.gridMap:getTileAtPosition(gameX, gameY)
        if def.type == 'place_tower' and def.payload and def.payload.tower then
            if tile then
                placed = self.gridMap:placeTowerAt(tile.x, tile.y, def.payload.tower, def.payload.level or 1)
            else
                placed = false
            end
        elseif def.type == 'modify_tower' and def.payload and def.payload.modifiers then
            if tile then
                placed = self.gridMap:applyTowerModifiers(tile.x, tile.y, def.payload.modifiers, def)
            else
                placed = false
            end
        elseif def.type == 'apply_path_effect' and def.payload then
            if tile then
                local waveTag = nil
                if self.waveManager and self.waveManager.getCurrentWaveIndex then
                    waveTag = self.waveManager:getCurrentWaveIndex()
                end
                if waveTag == nil and self.waveManager and self.waveManager.getNextWaveIndex then
                    waveTag = self.waveManager:getNextWaveIndex()
                end
                placed = self.gridMap:applyPathEffect(tile.x, tile.y, def.payload, def, waveTag)
            else
                placed = false
            end
        elseif def.type == 'apply_tower_buff' and def.payload then
            if tile then
                placed = self.gridMap:applyTowerBuff(tile.x, tile.y, def.payload, def)
            else
                placed = false
            end
        end
    else
        -- Non-targeting: enforce drag-up threshold (already locked in HandUI)
        if def.type == 'apply_core_shield' and def.payload and def.payload.shieldHp then
            if self.gridMap and self.gridMap.enemySpawnManager and self.gridMap.enemySpawnManager.addCoreShield then
                local waveTag = nil
                if self.waveManager and self.waveManager.getCurrentWaveIndex then
                    waveTag = self.waveManager:getCurrentWaveIndex()
                end
                if waveTag == nil and self.waveManager and self.waveManager.getNextWaveIndex then
                    -- no wave active yet, tag for the upcoming wave once it begins
                    waveTag = self.waveManager:getNextWaveIndex()
                end
                self.gridMap.enemySpawnManager:addCoreShield(def.payload.shieldHp, waveTag)
                placed = true
            end
        end
    end
    if not placed then
        -- refund energy and card if placement invalid
        self.deck:refundLastPlayed(def.id)
    else
        if self.handUI and self.handUI.onCardPlayed then
            self.handUI:onCardPlayed(info.cardIndex, def.id, startX, startY)
        end
        if self.bus and self.bus.emit then
            self.bus:emit('card_played', def, {
                x = gameX, y = gameY,
                tile = self.gridMap and self.gridMap:getTileAtPosition(gameX, gameY) or nil
            })
        end
    end
end

function love.resize(width, height)
    -- Handle window resize
    ResolutionManager:resize(width, height)
end

function Game:drawHUD()
    -- Draw a compact numeric core health at the top-right of the logical canvas
    local padding = Config.UI.PANEL_PADDING or 8
    local y = 8

    local coreHealth = 0
    local shield = 0
    if self.gridMap and self.gridMap.enemySpawnManager and self.gridMap.enemySpawnManager.getCoreHealth then
        coreHealth = self.gridMap.enemySpawnManager:getCoreHealth()
        if self.gridMap.enemySpawnManager.getCoreShield then
            shield = self.gridMap.enemySpawnManager:getCoreShield()
        end
    end
    local maxHealth = Config.GAME.CORE_HEALTH

    -- Numeric only, e.g., "10/10"; append shield if present
    local text
    if (shield or 0) > 0 then
        text = string.format("%d/%d  [Shield %d]", coreHealth, maxHealth, shield)
    else
        text = string.format("%d/%d", coreHealth, maxHealth)
    end

    local font = Theme.FONTS.MEDIUM
    local textW = font:getWidth(text)
    local textH = font:getHeight()
    local panelWidth = textW + padding * 2
    local panelHeight = textH + padding * 2
    local x = (Config.LOGICAL_WIDTH or 0) - panelWidth - 8

    Theme.drawPanel(x, y, panelWidth, panelHeight)
    -- Right-align text inside the panel
    local tx = x + panelWidth - padding - textW
    local ty = y + padding
    Theme.drawText(text, tx, ty, font, Theme.COLORS.WHITE)
end

function Game:loadCoinIcon()
    if self.coinIcon ~= nil then return self.coinIcon end
    local tracker = Config.UI.COIN_TRACKER
    if not tracker then
        self.coinIcon = false
        return nil
    end
    local filename = tracker.ICON or 'coin_1.png'
    local path = string.format('%s/%s', Config.ENTITIES_PATH, filename)
    if love.filesystem.getInfo(path) then
        local ok, img = pcall(love.graphics.newImage, path)
        if ok and img then
            if img.setFilter then
                img:setFilter('linear', 'linear')
            end
            self.coinIcon = img
            return img
        end
    end
    self.coinIcon = false
    return nil
end

function Game:getCoinCount()
    return self.coinCount or 0
end

function Game:addCoins(amount)
    if amount and amount > 0 then
        self.coinCount = (self.coinCount or 0) + amount
    end
end

function Game:spendCoins(amount)
    amount = amount or 0
    if amount <= 0 then return true end
    if (self.coinCount or 0) < amount then
        return false
    end
    self.coinCount = (self.coinCount or 0) - amount
    return true
end

function Game:handleEnemyKilled(enemyId, worldX, worldY)
    local dropCfg = Config.GAME.COIN_DROP or {}
    local spec = dropCfg[enemyId]
    if not spec then return end
    local chance = spec.chance or 0
    local coins = spec.coins or 0
    if coins <= 0 then return end
    if math.random() > chance then return end
    if worldX and worldY then
        self:onEnemyCoinsDropped(coins, worldX, worldY)
    else
        self:addCoins(coins)
    end
end

function Game:onEnemyCoinsDropped(coins, worldX, worldY)
    if not coins or coins <= 0 then return end
    local tracker = Config.GAME.COIN_DROP and Config.GAME.COIN_DROP.pickup or {}
    local duration = tracker.travelTime or 1
    local variance = tracker.travelTimeVariance or 0
    local arcHeight = tracker.arcHeight or -160
    local lateralJitter = tracker.lateralJitter or 0
    local startLift = tracker.startLift or 0
    local delayBetween = tracker.delayBetweenCoins or 0
    for i = 1, coins do
        local delay = (i - 1) * delayBetween
        local journey = duration + (math.random() * 2 - 1) * variance
        journey = math.max(0.25, journey)
        local jitter = (math.random() * 2 - 1) * lateralJitter
        local pickup = {
            startX = worldX + jitter,
            startY = worldY + startLift,
            controlX = worldX + jitter * 0.4,
            controlY = worldY + arcHeight,
            endX = self:getCoinTrackerTargetX(),
            endY = self:getCoinTrackerTargetY(),
            t = 0,
            duration = journey,
            delay = delay,
            collected = false
        }
        table.insert(self.coinPickups, pickup)
    end
end

function Game:getCoinTrackerTargetX()
    local tracker = Config.UI.COIN_TRACKER or {}
    local margin = tracker.MARGIN or 16
    local icon = self:loadCoinIcon()
    local iconScale = tracker.ICON_SCALE or 1
    local spacing = tracker.ICON_TEXT_SPACING or 8
    local fontKey = tracker.FONT or 'BOLD_MEDIUM'
    local font = Theme.FONTS[fontKey] or Theme.FONTS.BOLD_MEDIUM
    local x = margin
    if icon then
        local iw = icon:getWidth()
        x = x + iw * iconScale + spacing
    end
    local text = tostring(self.coinCount or 0)
    local textWidth = font:getWidth(text)
    return x + textWidth * 0.5
end

function Game:getCoinTrackerTargetY()
    local tracker = Config.UI.COIN_TRACKER or {}
    local margin = tracker.MARGIN or 16
    local offsetY = tracker.OFFSET_Y or 0
    local fontKey = tracker.FONT or 'BOLD_MEDIUM'
    local font = Theme.FONTS[fontKey] or Theme.FONTS.BOLD_MEDIUM
    local y = (Config.LOGICAL_HEIGHT or 0) - margin - font:getHeight() - offsetY
    return y + font:getHeight() * 0.5
end

local function quadraticBezier(p0x, p0y, p1x, p1y, p2x, p2y, t)
    local inv = 1 - t
    local x = inv * inv * p0x + 2 * inv * t * p1x + t * t * p2x
    local y = inv * inv * p0y + 2 * inv * t * p1y + t * t * p2y
    return x, y
end

function Game:updateCoinPickups(dt)
    if not self.coinPickups then return end
    for i = #self.coinPickups, 1, -1 do
        local p = self.coinPickups[i]
        if p.delay and p.delay > 0 then
            p.delay = math.max(0, p.delay - dt)
        else
            p.t = (p.t or 0) + dt
            if p.t >= p.duration then
                if not p.collected then
                    self:addCoins(1)
                    p.collected = true
                end
                table.remove(self.coinPickups, i)
            end
        end
    end
end

function Game:drawCoinPickups()
    if not self.coinPickups or #self.coinPickups == 0 then return end
    love.graphics.setColor(1, 1, 1, 1)
    local icon = self:loadCoinIcon()
    for _, p in ipairs(self.coinPickups) do
        if not p.collected then
            if p.delay and p.delay > 0 then
                -- still waiting
            else
                local t = math.max(0, math.min(1, (p.t or 0) / (p.duration or 1)))
                local x, y = quadraticBezier(p.startX, p.startY, p.controlX, p.controlY, p.endX, p.endY, t)
                local scale = Config.UI.COIN_TRACKER and Config.UI.COIN_TRACKER.ICON_SCALE or 1
                if icon then
                    love.graphics.draw(icon, x, y, 0, scale, scale, icon:getWidth() * 0.5, icon:getHeight() * 0.5)
                else
                    love.graphics.circle('fill', x, y, 6)
                end
            end
        end
    end
end

function Game:drawCoinTracker()
    local tracker = Config.UI.COIN_TRACKER
    if not tracker then return end

    local icon = self:loadCoinIcon()
    local coinCount = self:getCoinCount()

    local margin = tracker.MARGIN or 16
    local offsetY = tracker.OFFSET_Y or 0
    local iconScale = tracker.ICON_SCALE or 1
    local iconTextSpacing = tracker.ICON_TEXT_SPACING or 8
    local color = tracker.COLOR or Theme.COLORS.WHITE
    local shadowColor = tracker.SHADOW_COLOR or {0, 0, 0, 0.6}
    local fontKey = tracker.FONT or 'BOLD_MEDIUM'
    local font = Theme.FONTS[fontKey] or Theme.FONTS.BOLD_MEDIUM

    local x = margin
    local y = (Config.LOGICAL_HEIGHT or 0) - margin - font:getHeight() - offsetY

    if icon then
        local iw, ih = icon:getWidth(), icon:getHeight()
        local sx = iconScale
        local sy = iconScale
        local drawY = y + font:getHeight() * 0.5 - (ih * sy) * 0.5
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(icon, x, drawY, 0, sx, sy)
        x = x + iw * sx + iconTextSpacing
    end

    local text = tostring(coinCount)
    Theme.drawShadowText(text, x, y, font, color, shadowColor)
end

function Game:attemptTowerUpgrade(tower, targetLevel, cost)
    if not tower or not targetLevel then return false end
    cost = cost or 0
    if cost > 0 then
        if not self:spendCoins(cost) then
            return false
        end
    end
    if self.gridMap and self.gridMap.towerManager and self.gridMap.towerManager.upgradeTower then
        local ok = self.gridMap.towerManager:upgradeTower(tower, targetLevel)
        if ok then
            if self.gridMap and self.gridMap.onTowerUpgraded then
                self.gridMap:onTowerUpgraded(tower)
            end
            return true
        else
            if cost > 0 then
                self:addCoins(cost)
            end
        end
    end
    return false
end

function Game:attemptTowerDestroy(tower)
    if not tower then return false end
    if self.gridMap and self.gridMap.towerManager and self.gridMap.towerManager.destroyTower then
        return self.gridMap.towerManager:destroyTower(tower)
    end
    return false
end

return Game
