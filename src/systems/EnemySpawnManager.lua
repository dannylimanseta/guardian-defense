-- EnemySpawnManager.lua - Spawning and moving enemies along path tiles

local Config = require 'src/config/Config'
local Pathfinder = require 'src/systems/Pathfinder'
local moonshine = require 'src/libs/moonshine'
local Theme = require 'src/theme'

local EnemySpawnManager = {}
EnemySpawnManager.__index = EnemySpawnManager

function EnemySpawnManager:new(mapData)
    local self = setmetatable({}, EnemySpawnManager)
    self.mapData = mapData
    self.enemies = {}
    self.timeSinceLastSpawn = 0
    self.coreHealth = Config.GAME.CORE_HEALTH
    self.enemySprite = nil
    self.flashChains = {}
    -- Direct shader fallback for per-sprite white flash
    self.whitenShader = love.graphics.newShader([[
        extern number amount; // 0..1
        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 _){
            vec4 px = Texel(tex, tc) * color;
            vec3 outc = mix(px.rgb, vec3(1.0), clamp(amount, 0.0, 1.0));
            return vec4(outc, px.a);
        }
    ]])
    return self
end

local function gridToPixels(gridX, gridY, originX, originY, tileSize)
    local px = originX + (gridX - 1) * tileSize
    local py = originY + (gridY - 1) * tileSize
    return px, py
end

local function computePath(mapData, spawnPos, corePos)
    return Pathfinder:findPath(mapData, spawnPos.x, spawnPos.y, corePos.x, corePos.y)
end

function EnemySpawnManager:spawnEnemy()
    if not self.mapData or not self.mapData.special then return end
    local spawns = self.mapData.special.enemy_spawns or {}
    local core = self.mapData.special.core
    if #spawns == 0 or not core then
        if Config.GAME.DEBUG_MODE then
            print("Spawn failed: no spawn points or core not found")
        end
        return false
    end

    -- Round-robin or simple first spawn
    local spawnPos = spawns[1]
    local path = computePath(self.mapData, spawnPos, core)
    if not path or #path == 0 then
        if Config.GAME.DEBUG_MODE then
            print(string.format("Spawn failed: no path from (%d,%d) to core (%d,%d). Ensure spawn is adjacent to a path tile.",
                spawnPos.x, spawnPos.y, core.x, core.y))
        end
        return false
    end

    -- Enemy state
    local enemy = {
        gridX = spawnPos.x,
        gridY = spawnPos.y,
        path = path,
        pathIndex = 1,
        progress = 0, -- 0..1 along segment
        speedTilesPerSecond = Config.ENEMY.SPEED_TILES_PER_SECOND,
        t = 0, -- local time accumulator for bobbing
        bobPhase = math.random() * math.pi * 2,
        bobFreq = 10 + math.random() * 4, -- 10..14 Hz (faster)
        bobAmp = (0.02 + math.random() * 0.02), -- 0.02..0.04 of tile (smaller)
        hp = Config.ENEMY.DEFAULT_HP,
        maxHp = Config.ENEMY.DEFAULT_HP,
        -- hit effects
        hitFlashTime = 0,
        kox = 0, koy = 0, -- knockback offset (pixels)
        kvx = 0, kvy = 0,  -- knockback velocity (pixels/sec)
        krot = 0, krotVel = 0 -- rotational knock
    }
    table.insert(self.enemies, enemy)
    return true
end

function EnemySpawnManager:damageEnemy(index, amount, hitDX, hitDY, hitStrength)
    local e = self.enemies[index]
    if not e then return end
    e.hp = math.max(0, e.hp - (amount or 1))
    -- Trigger hit flash and knockback
    e.hitFlashTime = 0.12
    local strength = (hitStrength or 1) * Config.ENEMY.KNOCKBACK_VELOCITY_PPS
    if hitDX and hitDY then
        -- push enemy away from the projectile impact
        e.kvx = (e.kvx or 0) + (hitDX * strength)
        e.kvy = (e.kvy or 0) + (hitDY * strength)
        -- rotational impulse: rotate slightly based on hit direction
        e.krotVel = (e.krotVel or 0) + (-hitDX) * Config.ENEMY.KNOCKBACK_ROT_IMPULSE
    end
    if e.hp <= 0 then
        table.remove(self.enemies, index)
    end
end

function EnemySpawnManager:damageAll(amount)
    for i = #self.enemies, 1, -1 do
        self:damageEnemy(i, amount)
    end
end

function EnemySpawnManager:update(dt)
    -- Handle spawning cadence
    self.timeSinceLastSpawn = self.timeSinceLastSpawn + dt
    if #self.enemies < Config.ENEMY.MAX_ACTIVE and self.timeSinceLastSpawn >= Config.ENEMY.SPAWN_INTERVAL then
        self:spawnEnemy()
        self.timeSinceLastSpawn = 0
    end

    -- Advance enemies along path
    for i = #self.enemies, 1, -1 do
        local e = self.enemies[i]
        e.t = e.t + dt
        -- Decay hit flash
        if e.hitFlashTime and e.hitFlashTime > 0 then
            e.hitFlashTime = math.max(0, e.hitFlashTime - dt)
        end
        -- Integrate knockback velocity with damping
        if e.kvx and e.kvy then
            e.kox = (e.kox or 0) + e.kvx * dt
            e.koy = (e.koy or 0) + e.kvy * dt
            local damp = math.max(0, 1 - (Config.ENEMY.KNOCKBACK_DAMP * dt))
            e.kvx = e.kvx * damp
            e.kvy = e.kvy * damp
            -- bring offset back to zero slightly to avoid drift
            e.kox = e.kox * math.max(0, 1 - (Config.ENEMY.KNOCKBACK_RETURN_RATE * dt))
            e.koy = e.koy * math.max(0, 1 - (Config.ENEMY.KNOCKBACK_RETURN_RATE * dt))
        end
        -- Integrate rotational knockback with damping
        if e.krotVel then
            e.krot = (e.krot or 0) + e.krotVel * dt
            e.krotVel = e.krotVel * math.max(0, 1 - 10 * dt)
            e.krot = e.krot * math.max(0, 1 - 4 * dt)
        end
        local path = e.path
        if not path or e.pathIndex >= #path then
            -- Reached last node (assume core)
            self.coreHealth = math.max(0, self.coreHealth - Config.ENEMY.DAMAGE_ON_HIT)
            table.remove(self.enemies, i)
        else
            local a = path[e.pathIndex]
            local b = path[e.pathIndex + 1]
            local segmentTime = 1 / e.speedTilesPerSecond
            e.progress = e.progress + dt / segmentTime
            if e.progress >= 1 then
                e.progress = e.progress - 1
                e.pathIndex = e.pathIndex + 1
                e.gridX = b.x
                e.gridY = b.y
            end
        end
    end
end

function EnemySpawnManager:draw(originX, originY, tileSize)
    if not self.enemySprite then
        local path = string.format('%s/%s', Config.ENTITIES_PATH, 'enemy_1.png')
        if love.filesystem.getInfo(path) then
            self.enemySprite = love.graphics.newImage(path)
            self.enemySprite:setFilter('nearest', 'nearest')
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
    for _, e in ipairs(self.enemies) do
        local path = e.path
        local a = path[math.max(1, e.pathIndex)]
        local b = path[math.min(#path, e.pathIndex + 1)]
        local ax, ay = gridToPixels(a.x, a.y, originX, originY, tileSize)
        local bx, by = gridToPixels(b.x, b.y, originX, originY, tileSize)
        local x = ax + (bx - ax) * e.progress
        local y = ay + (by - ay) * e.progress
        -- Bobbing: sinusoidal vertical offset
        local bob = math.sin(e.t * e.bobFreq + e.bobPhase) * (tileSize * e.bobAmp)
        y = y - bob
        -- Apply knockback visual offset (pixel space)
        x = x + (e.kox or 0)
        y = y + (e.koy or 0)
        
        if self.enemySprite then
            local baseScaleX = tileSize / self.enemySprite:getWidth()
            local baseScaleY = tileSize / self.enemySprite:getHeight()
            local scaleX = baseScaleX * 0.6 -- reduce to 60%
            local scaleY = baseScaleY * 0.6
            -- center sprite in tile
            local drawX = x + (tileSize - self.enemySprite:getWidth() * scaleX) / 2
            local drawY = y + (tileSize - self.enemySprite:getHeight() * scaleY) / 2
            local cx = drawX + (self.enemySprite:getWidth() * scaleX) / 2
            local cy = drawY + (self.enemySprite:getHeight() * scaleY) / 2
            love.graphics.draw(self.enemySprite, cx, cy, (e.krot or 0), scaleX, scaleY, self.enemySprite:getWidth()/2, self.enemySprite:getHeight()/2)
            -- White flash overlay using Moonshine colorgradesimple (brighten to white)
            if e.hitFlashTime and e.hitFlashTime > 0 then
                local alpha = math.min(1, e.hitFlashTime / 0.12)
                -- Prefer direct shader for reliability
                self.whitenShader:send('amount', 0.85 * alpha + 0.15)
                local prevShader = love.graphics.getShader()
                love.graphics.setShader(self.whitenShader)
                love.graphics.draw(self.enemySprite, cx, cy, (e.krot or 0), scaleX, scaleY, self.enemySprite:getWidth()/2, self.enemySprite:getHeight()/2)
                love.graphics.setShader(prevShader)
            end

            -- Mini HP bar when damaged
            if e.hp < e.maxHp then
                local barCfg = Config.ENEMY_HP_BAR
                local barWidth = barCfg.WIDTH
                local barHeight = barCfg.HEIGHT
                local percent = e.hp / e.maxHp
                local barX = cx - (barWidth / 2)
                local barY = (drawY - 2) + barCfg.OFFSET_Y
                Theme.drawHealthBar(barX, barY, barWidth, barHeight, percent, barCfg.BG_COLOR, barCfg.FG_COLOR)
            end
        else
            love.graphics.setColor(1, 0.2, 0.2, 1)
            local size = (tileSize - 16) * 0.6
            love.graphics.rectangle('fill', x + (tileSize - size)/2, y + (tileSize - size)/2, size, size)
            love.graphics.setColor(1, 1, 1, 1)
        end
    end
end

function EnemySpawnManager:getEnemies()
    return self.enemies
end

function EnemySpawnManager:getCoreHealth()
    return self.coreHealth
end

return EnemySpawnManager


