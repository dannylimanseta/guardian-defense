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
local ProjectileManager = require 'src/systems/ProjectileManager'
local Theme = require 'src/theme'

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
    self.selectedTile = nil
    self.rangeRotateDeg = 0
    self.rangeAlpha = 0
    self.rangeBounceT = 0

    -- Enemy system
    self.enemySpawnManager = EnemySpawnManager:new(self.mapData)

    -- Tower sprites (lazy-loaded on first draw)
    self.towerBaseSprite = nil
    self.towerCrossbowSprite = nil

    print(string.format("Grid initialized: %dx%d tiles at (%d, %d)",
        self.columns, self.rows, self.gridX, self.gridY))
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
                    local isSpecial = tile.type == "entrance" or tile.type == "core"
                    local isEnemySpawn = tile.type == "enemy_spawn"
                    
                    if (pass == 1 and not isSpecial and not isEnemySpawn) or 
                       (pass == 2 and isEnemySpawn) or 
                       (pass == 3 and isSpecial) then
                        love.graphics.setColor(1, 1, 1, tile.opacity or 1)
                        local tileX = self.gridX + (tile.x - 1) * self.tileSize
                        local tileY = self.gridY + (tile.y - 1) * self.tileSize

                        if isSpecial then
                            tileY = tileY - 2 * self.tileSize
                        end

                        local scaleX = self.tileSize / (tile.width or self.sourceTileWidth)
                        local scaleY = self.tileSize / (tile.height or self.sourceTileHeight)
                        
                        -- Center the heart tile in its grid cell and shift down by 1 grid
                        if tile.type == "core" then
                            local offsetX = (self.tileSize - sprite:getWidth() * scaleX) / 2
                            local offsetY = (self.tileSize - sprite:getHeight() * scaleY) / 2
                            tileX = tileX + offsetX
                            tileY = tileY + offsetY + self.tileSize
                        end
                        
                        love.graphics.draw(sprite, tileX, tileY, 0, scaleX, scaleY)
                    end
                end
            end
        end
        
        -- Draw towers and enemies in pass 4 (above paths, below special tiles)
        if pass == 4 then
            self.towerManager:draw(self.gridX, self.gridY, self.tileSize)
            self.enemySpawnManager:draw(self.gridX, self.gridY, self.tileSize)
        end

        -- Draw projectiles on top in pass 5
        if pass == 5 then
            self.projectileManager:draw(self.gridX, self.gridY, self.tileSize)
        end
    end

    love.graphics.setColor(1, 1, 1, 1)

    if self.hoveredTile then
        love.graphics.setColor(Config.COLORS.HOVER_TILE)
        local tileX = self.gridX + (self.hoveredTile.x - 1) * self.tileSize
        local tileY = self.gridY + (self.hoveredTile.y - 1) * self.tileSize
        love.graphics.rectangle("fill", tileX, tileY, self.tileSize, self.tileSize)
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
			local baseRadius = (Config.TOWER.RANGE_TILES or 0) * self.tileSize
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
            if Config.GAME.DEBUG_MODE then
                print(string.format("Selected tile: (%d, %d)", tile.x, tile.y))
            end
        end
    end
end

function GridMap:mousemoved(x, y, dx, dy)
    local tile = self:getTileAtPosition(x, y)
    self.hoveredTile = tile
end

-- External hover control used during card dragging: show hover only when eligible
function GridMap:setHoverFromPlacement(tile, eligible)
    if eligible then
        self.hoveredTile = tile
    else
        self.hoveredTile = nil
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
    if key == "space" then
        -- Clear selection
        self.selectedTile = nil
        print("Selection cleared")
    elseif key == "r" then
        -- Reset grid
        self:init()
        print("Grid reset")
    elseif key == "s" then
        -- Spawn one enemy immediately
        local ok = self.enemySpawnManager:spawnEnemy()
        if ok then
            print("Enemy spawned")
        else
            print("Enemy spawn failed (see debug log)")
        end
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

function GridMap:placeTowerAt(x, y)
    if not self:isBuildSpot(x, y) then return false end
    if self:isOccupied(x, y) then return false end
    self.towerManager:placeTower(x, y)
    if Config.GAME.DEBUG_MODE then
        print(string.format("Tower placed at: (%d, %d)", x, y))
    end
    return true
end

function GridMap:update(dt)
    -- Update enemy system
    self.enemySpawnManager:update(dt)

    -- Update towers (targeting and firing)
    local projectiles = self.projectileManager:get()
    local enemies = self.enemySpawnManager:getEnemies()
    self.towerManager:update(dt, self.tileSize, enemies, projectiles)

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

    -- Bounce timer when becoming visible
    if targetAlpha > 0 and self.rangeAlpha == 0 then
        self.rangeBounceT = 0
    end
    if self.rangeAlpha > 0 then
        self.rangeBounceT = (self.rangeBounceT or 0) + dt
    end
end

-- projectiles handled by ProjectileManager

return GridMap
