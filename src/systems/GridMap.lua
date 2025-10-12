-- GridMap.lua - Grid-based map system
-- Handles tile rendering, mouse interaction, and grid logic

local Config = require 'src/config/Config'
local MapLoader = require 'src/utils/MapLoader'
if type(MapLoader) ~= 'table' then
    package.loaded['src/utils/MapLoader'] = nil
    MapLoader = require 'src/utils/MapLoader'
end
local EnemySpawnManager = require 'src/systems/EnemySpawnManager'
local TowerManager = require 'src/systems/TowerManager'
local TowerDefs = require 'src/data/towers'
local ProjectileManager = require 'src/systems/ProjectileManager'
local Theme = require 'src/theme'
local Moonshine = require 'src/libs/moonshine'

local GridMap = {}
GridMap.__index = GridMap

function GridMap:new()
    local self = setmetatable({}, GridMap)
    return self
end

function GridMap:init()
    -- Load map from TMX
    self.mapData = MapLoader:load("level_1")
    if not self.mapData or not self.mapData.tiles then
        error("Failed to load map data for level_1")
    end

    -- Map dimensions and tile sizing
    self.columns = self.mapData.width
    self.rows = self.mapData.height
    self.sourceTileWidth = self.mapData.tileWidth
    self.sourceTileHeight = self.mapData.tileHeight
    self.tileSize = Config.TILE_SIZE
    self.tiles = self.mapData.tiles
    self.layers = self.mapData.layers
    self.specialTiles = self.mapData.special
    self.towerManager = TowerManager:new()
    self.projectileManager = ProjectileManager:new()

    -- Calculate grid position (centered on screen)
    self.gridWidth = self.columns * self.tileSize
    self.gridHeight = self.rows * self.tileSize
    self.gridX = (Config.LOGICAL_WIDTH - self.gridWidth) / 2
    self.gridY = (Config.LOGICAL_HEIGHT - self.gridHeight) / 2

    -- Mouse interaction state
    self.hoveredTile = nil
    self.showHoverRect = false
	self.hoveredTower = nil
    self.selectedTile = nil
    self.rangeRotateDeg = 0
    self.rangeAlpha = 0
    self.rangeBounceT = 0
    self.infoPanelAlpha = 0

    -- Enemy system
    self.enemySpawnManager = EnemySpawnManager:new(self.mapData)

    -- Tower sprites (lazy-loaded on first draw)
    self.towerBaseSprite = nil
    self.towerCrossbowSprite = nil
    -- glow effect for placement hover circle
    self.hoverGlow = Moonshine(Config.LOGICAL_WIDTH, Config.LOGICAL_HEIGHT, Moonshine.effects.glow)
    self.hoverGlow.glow.min_luma = 0.0
    self.hoverGlow.glow.strength = 5
end

-- (update merged below with towers/projectiles logic)

function GridMap:draw()
    -- Draw grid background
    love.graphics.setColor(Config.COLORS.GRID_BACKGROUND)
    love.graphics.rectangle("fill", self.gridX, self.gridY, self.gridWidth, self.gridHeight)
    
    -- Draw grid lines
    -- Removed grid border/lines for clean look
    
    -- Draw tiles in layers (pass 1: normal tiles, pass 2: enemy spawns, pass 3: special tiles, pass 4: towers & enemies, pass 5: projectiles)
    for pass = 1, 5 do
        for _, layer in ipairs(self.layers) do
            for _, tile in ipairs(layer.tiles) do
                local sprite = tile.sprite
                if sprite then
                    local isSpecial = tile.type == "entrance" or tile.type == "core" or tile.type == "pillar"
                    local isEnemySpawn = tile.type == "enemy_spawn"
                    
                    if (pass == 1 and not isSpecial and not isEnemySpawn) or 
                       (pass == 2 and isEnemySpawn) or 
                       (pass == 3 and isSpecial) then
                        love.graphics.setColor(1, 1, 1, tile.opacity or 1)
                        local tileX = self.gridX + (tile.x - 1) * self.tileSize
                        local tileY = self.gridY + (tile.y - 1) * self.tileSize

                        if isSpecial and tile.type ~= "core" then
                            tileY = tileY - 2 * self.tileSize
                        end

                        local scaleX = self.tileSize / (tile.width or self.sourceTileWidth)
                        local scaleY = self.tileSize / (tile.height or self.sourceTileHeight)
                        
                        -- Center the heart tile in its grid cell (no manual grid shift)
                        if tile.type == "core" then
                            -- If a TMX core object exists, skip drawing the tile-based core to follow TMX object exactly
                            if self.specialTiles and self.specialTiles.core and self.specialTiles.core.px then
                                goto skip_tile_draw
                            end
                            local offsetX = (self.tileSize - sprite:getWidth() * scaleX) / 2
                            local offsetY = (self.tileSize - sprite:getHeight() * scaleY) / 2
                            tileX = tileX + offsetX
                            tileY = tileY + offsetY
                        end
                        
                        -- Support flipped tiles from TMX
                        local sx = scaleX * ((tile.flipX and -1) or 1)
                        local sy = scaleY * ((tile.flipY and -1) or 1)
                        local ox = (tile.flipX and sprite:getWidth()) or 0
                        local oy = (tile.flipY and sprite:getHeight()) or 0
                        love.graphics.draw(sprite, tileX + (tile.flipX and sprite:getWidth() * scaleX or 0), tileY + (tile.flipY and sprite:getHeight() * scaleY or 0), 0, sx, sy)
                        ::skip_tile_draw::
                    end
                end
            end
        end

        -- Draw core sprite from TMX object coordinates to follow TMX exactly (after special tiles pass)
		if pass == 3 and self.specialTiles and self.specialTiles.core and self.specialTiles.core.px then
			self.coreSprite = self.coreSprite or (function()
				local p = string.format('%s/%s', Config.TILESET_PATH, 'heart_1.png')
				if love.filesystem.getInfo(p) then
					local img = love.graphics.newImage(p)
					img:setFilter('nearest', 'nearest')
					return img
				end
				return nil
			end)()
			self.coreShieldSprite = self.coreShieldSprite or (function()
				local p = 'assets/images/effects/fx_shield.png'
				if love.filesystem.getInfo(p) then
					local img = love.graphics.newImage(p)
					img:setFilter('linear', 'linear')
					return img
				end
				return nil
			end)()
			if self.coreSprite then
				local px = self.specialTiles.core.px or 0
				local py = self.specialTiles.core.py or 0
				local pcx = self.specialTiles.core.pcx or (px + self.coreSprite:getWidth() / 2)
				local pcy = self.specialTiles.core.pcy or (py + self.coreSprite:getHeight() / 2)
				local drawX = self.gridX + pcx - self.coreSprite:getWidth() / 2
				local drawY = self.gridY + pcy - self.coreSprite:getHeight() / 2
				love.graphics.setColor(1,1,1,1)
				love.graphics.draw(self.coreSprite, drawX, drawY)
				local vis = self.enemySpawnManager and self.enemySpawnManager.coreShieldVisual
				local shieldHp = (self.enemySpawnManager and self.enemySpawnManager:getCoreShield()) or 0
				if vis and (vis.active or (vis.alpha or 0) > 0 or shieldHp > 0) and self.coreShieldSprite then
					local baseAlpha = math.max(vis.alpha or 0, (shieldHp > 0) and 0.75 or 0)
					if baseAlpha > 0 then
						local pulse = math.sin((vis.pulse or 0) * 1.2) * 0.04
						local bounce = 1 + math.sin((vis.bounceT or 0) * 6) * 0.08
						local scale = (1.08 + pulse) * 1.3
						local img = self.coreShieldSprite
						local iw, ih = img:getWidth(), img:getHeight()
						local centerX = self.gridX + pcx
						local centerY = self.gridY + pcy - 23 - (bounce - 1) * 10
						local prevBlend, prevAlpha = love.graphics.getBlendMode()
						love.graphics.setBlendMode('add')
						love.graphics.setColor(1, 1, 1, baseAlpha)
						love.graphics.draw(img, centerX, centerY, 0, scale * bounce, scale * bounce, iw / 2, ih / 2)
						if prevBlend then
							love.graphics.setBlendMode(prevBlend, prevAlpha)
						else
							love.graphics.setBlendMode('alpha')
						end
						love.graphics.setColor(1,1,1,1)
					end
				end
			end
		end
        
        -- Draw towers and enemies in pass 4 (above paths, below special tiles)
        if pass == 4 then
            self.towerManager:draw(self.gridX, self.gridY, self.tileSize)
            self.enemySpawnManager:draw(self.gridX, self.gridY, self.tileSize)
            -- Optional in-world core HP bar (disabled by default in favor of HUD)
            if (Config.UI and Config.UI.SHOW_CORE_HEALTH_ABOVE_CORE) and self.specialTiles and self.specialTiles.core then
                local coreX, coreY
                if self.specialTiles.core.pcx and self.specialTiles.core.pcy then
                    coreX = self.gridX + self.specialTiles.core.pcx
                    coreY = self.gridY + self.specialTiles.core.pcy
                else
                    local cx, cy = self.specialTiles.core.x, self.specialTiles.core.y
                    coreX = self.gridX + (cx - 0.5) * self.tileSize
                    coreY = self.gridY + (cy - 0.5) * self.tileSize
                end
                local barCfg = Config.CORE_HP_BAR or { WIDTH = 36, HEIGHT = 4, OFFSET_Y = -50, BG_COLOR = {1,1,1,0.2}, FG_COLOR = {1,1,1,1}, CORNER_RADIUS = 2 }
                local coreHealth = 0
                if self.enemySpawnManager and self.enemySpawnManager.getCoreHealth then
                    coreHealth = self.enemySpawnManager:getCoreHealth()
                end
                local maxHealth = Config.GAME.CORE_HEALTH or 5
                if maxHealth and maxHealth > 0 then
                    local percent = math.max(0, math.min(1, coreHealth / maxHealth))
                    local barW = barCfg.WIDTH or 36
                    local barH = barCfg.HEIGHT or 4
                    local barX = coreX - barW / 2
                    local barY = coreY + (barCfg.OFFSET_Y or -50)
                    local radius = barCfg.CORNER_RADIUS or 2
                    Theme.drawHealthBar(barX, barY, barW, barH, percent, barCfg.BG_COLOR, barCfg.FG_COLOR, radius)
                    love.graphics.setColor(1,1,1,1)
                end
            end
        end

        -- Draw projectiles on top in pass 5
        if pass == 5 then
            self.projectileManager:draw(self.gridX, self.gridY, self.tileSize)
        end
    end

    love.graphics.setColor(1, 1, 1, 1)

    if self.hoveredTile and self.showHoverRect then
        local tileX = self.gridX + (self.hoveredTile.x - 1) * self.tileSize
        local tileY = self.gridY + (self.hoveredTile.y - 1) * self.tileSize
        local cx = tileX + self.tileSize * 0.5
        local cy = tileY + self.tileSize * 0.5
        local r = self.tileSize * 0.07
        -- draw the glow-blurred circle via moonshine glow chain
        self.hoverGlow(function()
            love.graphics.setBlendMode('add')
            love.graphics.setColor(1, 1, 1, 1.0)
            love.graphics.circle('fill', cx, cy, r)
            love.graphics.setBlendMode('alpha')
        end)
    end
    
    -- Draw selected tile
    if self.selectedTile then
        love.graphics.setColor(Config.COLORS.SELECTED_TILE)
        local tileX = self.gridX + (self.selectedTile.x - 1) * self.tileSize
        local tileY = self.gridY + (self.selectedTile.y - 1) * self.tileSize
        love.graphics.rectangle("fill", tileX, tileY, self.tileSize, self.tileSize)

		-- If a tower is selected, draw its range as a dotted circle
		local tower = self.towerManager:getTowerAt(self.selectedTile.x, self.selectedTile.y)
		if tower then
			local cx = self.gridX + (tower.x - 0.5) * self.tileSize
			local cy = self.gridY + (tower.y - 0.5) * self.tileSize
			local stats = TowerDefs.getStats(tower.towerId or 'crossbow', tower.level or 1)
			local baseRadius = (stats.rangePx or (Config.TOWER.RANGE_TILES * self.tileSize))
			local rcfg = Config.TOWER.RANGE_INDICATOR or {}
			local bounceScale = rcfg.BOUNCE_SCALE or 0
			local bounceDur = math.max(0.001, rcfg.BOUNCE_DURATION or 0.25)
			local bounce = 0
			if self.rangeBounceT and self.rangeBounceT < bounceDur then
				local t = self.rangeBounceT / bounceDur
				-- easeOutBack-like overshoot curve
				local s = 1.70158
				bounce = ((t-1)*(t-1)*((s+1)*(t-1)+s)+1) - 1
				bounce = bounce * bounceScale * baseRadius
			end
			local radius = baseRadius + bounce
			-- additive soft fill with fade
			if rcfg.FILL_ENABLED and self.rangeAlpha > 0 then
				Theme.drawAdditiveCircleFill(cx, cy, radius, (rcfg.FILL_ALPHA or 0.05) * self.rangeAlpha)
			end
			Theme.drawDottedCircle(
				cx,
				cy,
				radius,
				rcfg.DASH_DEG or 8,
				rcfg.GAP_DEG or 8,
				rcfg.LINE_WIDTH or 1,
				{(rcfg.COLOR and rcfg.COLOR[1] or 1), (rcfg.COLOR and rcfg.COLOR[2] or 1), (rcfg.COLOR and rcfg.COLOR[3] or 1), (rcfg.COLOR and rcfg.COLOR[4] or 0.7) * (self.rangeAlpha or 1)},
				rcfg.ROTATE_ENABLED and (self.rangeRotateDeg or 0) or 0
			)
		end
    end
    
    -- Reset color
    love.graphics.setColor(1, 1, 1, 1)
end

-- projectiles handled by ProjectileManager

function GridMap:mousepressed(x, y, button)
    if button == 1 then -- Left click
        local tile = self:getTileAtPosition(x, y)
        if tile then
            self.selectedTile = tile
            -- Selection only; placement is gated by card play via Game:mousereleased
            -- no debug print
        end
    end
end

function GridMap:mousemoved(x, y, dx, dy)
    local tile = self:getTileAtPosition(x, y)
    self.hoveredTile = tile
    -- derive hovered tower if any
    self.hoveredTower = nil
    if tile then
        local t = self.towerManager:getTowerAt(tile.x, tile.y)
        if t then self.hoveredTower = t end
    end
end

-- External hover control used during card dragging: show hover only when eligible
function GridMap:setHoverFromPlacement(tile, eligible)
    if eligible then
        self.hoveredTile = tile
        self.showHoverRect = true
    else
        self.hoveredTile = nil
        self.showHoverRect = false
    end
end

function GridMap:getTileAtPosition(x, y)
    -- Check if position is within grid bounds
    if x < self.gridX or x > self.gridX + self.gridWidth or
       y < self.gridY or y > self.gridY + self.gridHeight then
        return nil
    end
    
    -- Calculate grid coordinates
    local gridX = math.floor((x - self.gridX) / self.tileSize) + 1
    local gridY = math.floor((y - self.gridY) / self.tileSize) + 1
    
    -- Validate grid coordinates
    if gridX >= 1 and gridX <= self.columns and
       gridY >= 1 and gridY <= self.rows then
        return {x = gridX, y = gridY}
    end
    
    return nil
end

function GridMap:keypressed(key)
    if key == "r" then
        -- Reset grid
        self:init()
    elseif key == "s" then
        -- Spawn one enemy immediately
        local ok = self.enemySpawnManager:spawnEnemy()
        -- no debug prints on spawn
    end
end

function GridMap:isBuildSpot(x, y)
    if not self.specialTiles or not self.specialTiles.build_spots then return false end
    for _, pos in ipairs(self.specialTiles.build_spots) do
        if pos.x == x and pos.y == y then return true end
    end
    return false
end

function GridMap:isOccupied(x, y)
    for _, t in ipairs(self.towerManager:getTowers()) do
        if t.x == x and t.y == y then return true end
    end
    return false
end

-- placement handled by TowerManager

function GridMap:placeTowerAt(x, y, towerId, level)
    if not self:isBuildSpot(x, y) then return false end
    if self:isOccupied(x, y) then return false end
    self.towerManager:placeTower(x, y, towerId, level)
    return true
end

function GridMap:update(dt)
    -- Update enemy system
    self.enemySpawnManager:update(dt)

    -- Update towers (targeting and firing)
    local projectiles = self.projectileManager:get()
    local enemies = self.enemySpawnManager:getEnemies()
    self.towerManager:update(dt, self.tileSize, enemies, projectiles, self.enemySpawnManager)

    -- Update projectiles
    self.projectileManager:update(
        dt,
        self.gridX,
        self.gridY,
        self.gridWidth,
        self.gridHeight,
        self.tileSize,
        enemies,
        self.enemySpawnManager,
        self.onHitScreenMove
    )

    -- Animate range indicator rotation
    local rcfg = Config.TOWER.RANGE_INDICATOR or {}
    if rcfg.ROTATE_ENABLED then
        local speed = rcfg.ROTATE_DEG_PER_SEC or 90
        self.rangeRotateDeg = ((self.rangeRotateDeg or 0) + speed * dt) % 360
    end

    -- Fade in/out alpha
    local targetAlpha = (self.selectedTile and self.towerManager:getTowerAt(self.selectedTile.x, self.selectedTile.y)) and 1 or 0
    local fadeIn = rcfg.FADE_IN_SPEED or 8
    local fadeOut = rcfg.FADE_OUT_SPEED or 6
    if targetAlpha > self.rangeAlpha then
        self.rangeAlpha = math.min(1, self.rangeAlpha + fadeIn * dt)
    else
        self.rangeAlpha = math.max(0, self.rangeAlpha - fadeOut * dt)
    end

    -- Reset bounce when visibility toggles off->on (avoid reliance on exact alpha==0)
    if targetAlpha > 0 and ((self.prevRangeTargetAlpha or 0) == 0) then
        self.rangeBounceT = 0
    end
    self.prevRangeTargetAlpha = targetAlpha
    if self.rangeAlpha > 0 then
        self.rangeBounceT = (self.rangeBounceT or 0) + dt
    end
end

-- projectiles handled by ProjectileManager

function GridMap:drawInfoPanel()
    -- Tower Info Panel (top-left) when hovered or selected tower, drawn in screen space (no shake)
    local infoTower = self.hoveredTower or (self.selectedTile and self.towerManager:getTowerAt(self.selectedTile.x, self.selectedTile.y)) or nil
    if infoTower then
        local pad = 12
        local panelW = math.floor(320 * 0.7)
        local x = pad
        local y = pad
        local titleFont = Theme.FONTS.LARGE
        local labelFont = Theme.FONTS.MEDIUM
        local valueFont = Theme.FONTS.MEDIUM
        local stats = TowerDefs.getStats(infoTower.towerId or 'crossbow', infoTower.level or 1)
        local titleH = titleFont:getHeight()
        local levelH = labelFont:getHeight()
        local lineH = valueFont:getHeight() + 6
        local rows = 5
        local panelH = pad + titleH + 6 + levelH + 8 + rows * lineH + pad
        -- update fade alpha
        self.infoPanelAlpha = math.min(1, (self.infoPanelAlpha or 0) + 6 * love.timer.getDelta())
        love.graphics.setColor(0, 0, 0, 0.3 * (self.infoPanelAlpha or 1))
        love.graphics.rectangle('fill', x, y, panelW, panelH)
        local accent = {0.4039, 0.6745, 0.5922, 1}
        local tx = x + pad
        local ty = y + pad
        Theme.drawText((stats.name or 'Tower'), tx, ty, titleFont, {1,1,1,(self.infoPanelAlpha or 1)})
        ty = ty + titleH + 6
        Theme.drawText(string.format('LEVEL %d', infoTower.level or 1), tx, ty, labelFont, {accent[1],accent[2],accent[3],(self.infoPanelAlpha or 1)})
        ty = ty + levelH + 8
        local vx = x + panelW - pad
        local function row(label, value)
            Theme.drawText(label, tx, ty, labelFont, {1,1,1,(self.infoPanelAlpha or 1)})
            local w = valueFont:getWidth(value)
            Theme.drawText(value, vx - w, ty, valueFont, {accent[1],accent[2],accent[3],(self.infoPanelAlpha or 1)})
            ty = ty + lineH
        end
        if (infoTower.towerId or 'crossbow') == 'fire' then
            row('Fire Rate', string.format('%.2fs', stats.fireCooldown or 0))
            row('Range', tostring(stats.rangePx or (Config.TOWER.RANGE_TILES * self.tileSize)))
            row('Burn Damage', tostring(stats.burnDamage or 0))
            row('Burn Ticks', tostring(stats.burnTicks or 0))
            row('Tick Interval', string.format('%.2fs', stats.burnTickInterval or 0.5))
        else
            row('Damage', string.format('%d-%d', stats.damageMin or 0, stats.damageMax or 0))
            row('Crit Damage', string.format('%d-%d', stats.critDamageMin or 0, stats.critDamageMax or 0))
            row('Crit Chance', string.format('%d%%', math.floor((stats.critChance or 0) * 100 + 0.5)))
            row('Fire Rate', string.format('%.1fs', stats.fireCooldown or 0))
            row('Range', tostring(stats.rangePx or (Config.TOWER.RANGE_TILES * self.tileSize)))
        end
    else
        if self.infoPanelAlpha and self.infoPanelAlpha > 0 then
            self.infoPanelAlpha = math.max(0, self.infoPanelAlpha - 6 * love.timer.getDelta())
        end
    end
end

return GridMap
