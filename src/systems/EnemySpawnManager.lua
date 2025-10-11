-- EnemySpawnManager.lua - Spawning and moving enemies along path tiles

local Config = require 'src/config/Config'
local Pathfinder = require 'src/systems/Pathfinder'
local moonshine = require 'src/libs/moonshine'
local Theme = require 'src/theme'
local Enemies = require 'src/data/enemies'

local EnemySpawnManager = {}
EnemySpawnManager.__index = EnemySpawnManager

function EnemySpawnManager:new(mapData)
    local self = setmetatable({}, EnemySpawnManager)
    self.mapData = mapData
    self.enemies = {}
    self.timeSinceLastSpawn = 0
    self.coreHealth = Config.GAME.CORE_HEALTH
    self.enemySprites = {}
    self.flashChains = {}
    self.floaters = {}
    -- Direct shader fallback for per-sprite white flash
    self.whitenShader = love.graphics.newShader([[
        extern number amount; // 0..1
        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 _){
            vec4 px = Texel(tex, tc) * color;
            vec3 outc = mix(px.rgb, vec3(1.0), clamp(amount, 0.0, 1.0));
            return vec4(outc, px.a);
        }
    ]])
    -- PostFX chains for hit bloom
    -- We keep a single chain sized to logical resolution and reuse it per enemy draw call
    self.hitGlow = moonshine(Config.LOGICAL_WIDTH, Config.LOGICAL_HEIGHT, moonshine.effects.glow)
    self.hitGlow.glow.min_luma = Config.ENEMY.HIT_GLOW_MIN_LUMA or 0.0
    self.hitGlow.glow.strength = Config.ENEMY.HIT_GLOW_STRENGTH or 10
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

function EnemySpawnManager:getSpriteFor(enemyId)
    local id = enemyId or 'enemy_1'
    if self.enemySprites[id] then return self.enemySprites[id] end
    local filename = string.format('%s/%s.png', Config.ENTITIES_PATH, id)
    local path = filename
    if not love.filesystem.getInfo(path) and id ~= 'enemy_1' then
        -- fallback to enemy_1 if specific art not found
        path = string.format('%s/%s.png', Config.ENTITIES_PATH, 'enemy_1')
    end
    if love.filesystem.getInfo(path) then
        local img = love.graphics.newImage(path)
        img:setFilter('nearest', 'nearest')
        self.enemySprites[id] = img
        return img
    end
    return nil
end

local function getEnemyBase(defId)
    local def = (Enemies or {})[defId or 'enemy_1'] or (Enemies and Enemies['enemy_1']) or nil
    if def then
        return def.speedTilesPerSecond or Config.ENEMY.SPEED_TILES_PER_SECOND,
               def.hp or Config.ENEMY.DEFAULT_HP,
               def.reward or 1
    end
    return Config.ENEMY.SPEED_TILES_PER_SECOND, Config.ENEMY.DEFAULT_HP, 1
end

-- Public API for WaveManager: request spawning a specific enemy at a given spawn index
function EnemySpawnManager:requestSpawn(enemyId, spawnIndex, modifiers)
    if not self.mapData or not self.mapData.special then return false end
    local spawns = self.mapData.special.enemy_spawns or {}
    local core = self.mapData.special.core
    if #spawns == 0 or not core then return false end

    local index = math.max(1, math.min(#spawns, tonumber(spawnIndex) or 1))
    local spawnPos = spawns[index]
    local path = computePath(self.mapData, spawnPos, core)
    if not path or #path == 0 then return false end

    local baseSpeed, baseHp, baseReward = getEnemyBase(enemyId)
    local speedTps = baseSpeed
    local hp = baseHp
    local reward = baseReward
    if modifiers then
        if modifiers.speed and modifiers.speed ~= 1 then speedTps = speedTps * modifiers.speed end
        if modifiers.hp and modifiers.hp ~= 1 then hp = math.floor(hp * modifiers.hp + 0.5) end
        if modifiers.reward and modifiers.reward ~= 1 then reward = reward * modifiers.reward end
    end

    local enemy = {
        enemyId = enemyId or 'enemy_1',
        gridX = spawnPos.x,
        gridY = spawnPos.y,
        path = path,
        pathIndex = 1,
        progress = 0,
        speedTilesPerSecond = speedTps,
        t = 0,
        bobPhase = math.random() * math.pi * 2,
        bobFreq = 10 + math.random() * 4,
        bobAmp = (0.02 + math.random() * 0.02),
        hp = hp,
        maxHp = hp,
        reward = reward,
        -- hit effects
        hitFlashTime = 0,
        kox = 0, koy = 0,
        kvx = 0, kvy = 0,
        krot = 0, krotVel = 0
    }
    table.insert(self.enemies, enemy)
    return true
end

function EnemySpawnManager:spawnEnemy()
    if not self.mapData or not self.mapData.special then return end
    local spawns = self.mapData.special.enemy_spawns or {}
    local core = self.mapData.special.core
    if #spawns == 0 or not core then
        return false
    end

    -- Round-robin or simple first spawn
    local spawnPos = spawns[1]
    local path = computePath(self.mapData, spawnPos, core)
    if not path or #path == 0 then
        return false
    end

    local baseSpeed, baseHp = getEnemyBase('enemy_1')

    -- Enemy state
    local enemy = {
        enemyId = 'enemy_1',
        gridX = spawnPos.x,
        gridY = spawnPos.y,
        path = path,
        pathIndex = 1,
        progress = 0, -- 0..1 along segment
        speedTilesPerSecond = baseSpeed,
        t = 0, -- local time accumulator for bobbing
        bobPhase = math.random() * math.pi * 2,
        bobFreq = 10 + math.random() * 4, -- 10..14 Hz (faster)
        bobAmp = (0.02 + math.random() * 0.02), -- 0.02..0.04 of tile (smaller)
        hp = baseHp,
        maxHp = baseHp,
        -- hit effects
        hitFlashTime = 0,
        kox = 0, koy = 0, -- knockback offset (pixels)
        kvx = 0, kvy = 0,  -- knockback velocity (pixels/sec)
        krot = 0, krotVel = 0 -- rotational knock
    }
    table.insert(self.enemies, enemy)
    return true
end

function EnemySpawnManager:damageEnemy(index, amount, hitDX, hitDY, hitStrength, isCrit)
    local e = self.enemies[index]
    if not e then return end
    e.hp = math.max(0, e.hp - (amount or 1))
    -- Trigger hit flash and knockback
    e.hitFlashTime = Config.ENEMY.HIT_FLASH_DURATION or 0.12
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
    -- spawn floating damage text near the enemy's current tile center (pixel space relative to grid origin)
    local jx = (hitDX or 0) * 6
    local jy = (hitDY or 0) * 6
    -- anchor at the enemy's current visual position along the path
    local a = e.path[math.max(1, e.pathIndex)]
    local b = e.path[math.min(#e.path, e.pathIndex + 1)] or a
    local ax = (a.x - 0.5) * Config.TILE_SIZE
    local ay = (a.y - 0.5) * Config.TILE_SIZE
    local bx = (b.x - 0.5) * Config.TILE_SIZE
    local by = (b.y - 0.5) * Config.TILE_SIZE
    local baseX = ax + (bx - ax) * (e.progress or 0)
    local baseY = ay + (by - ay) * (e.progress or 0)
    -- include current knockback offsets for better alignment
    baseX = baseX + (e.kox or 0)
    baseY = baseY + (e.koy or 0)
    self.floaters[#self.floaters+1] = {
        baseX = baseX + jx,
        baseY = baseY + jy,
        dirX = (hitDX or 0),
        dirY = (hitDY or -1),
        amp = 8, -- further reduced initial travel distance (pixels)
        holdSec = 0.5, -- linger duration at peak
        endFactor = 0.5, -- return only 35% back toward origin
        text = (isCrit and (tostring(math.floor(amount + 0.5)) .. "!") or tostring(math.floor(amount + 0.5))),
        isCrit = isCrit and true or false,
        age = 0,
        life = 0.5
    }
end

function EnemySpawnManager:damageAll(amount)
    for i = #self.enemies, 1, -1 do
        self:damageEnemy(i, amount)
    end
end

function EnemySpawnManager:update(dt)
    -- Handle spawning cadence (legacy debug spawner)
    self.timeSinceLastSpawn = self.timeSinceLastSpawn + dt
    if #self.enemies < Config.ENEMY.MAX_ACTIVE and self.timeSinceLastSpawn >= Config.ENEMY.SPAWN_INTERVAL then
        -- Commented out to avoid interfering with wave system; keep for manual 's' debug key
        -- self:spawnEnemy()
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
    -- update floating damage numbers (age/fade only; position computed analytically on draw)
    for i = #self.floaters, 1, -1 do
        local f = self.floaters[i]
        f.age = f.age + dt
        if f.age >= f.life then table.remove(self.floaters, i) end
    end
end

function EnemySpawnManager:draw(originX, originY, tileSize)
    love.graphics.setColor(1, 1, 1, 1)
    for _, e in ipairs(self.enemies) do
        -- Reset draw state to avoid leaked alpha/blend/shader from previous draws
        love.graphics.setShader()
        love.graphics.setBlendMode('alpha')
        love.graphics.setColor(1, 1, 1, 1)
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
        
        local sprite = self:getSpriteFor(e.enemyId)
        if sprite then
            local baseScaleX = tileSize / sprite:getWidth()
            local baseScaleY = tileSize / sprite:getHeight()
            local scaleX = baseScaleX * 0.6 -- reduce to 60%
            local scaleY = baseScaleY * 0.6
            -- center sprite in tile
            local drawX = x + (tileSize - sprite:getWidth() * scaleX) / 2
            local drawY = y + (tileSize - sprite:getHeight() * scaleY) / 2
            local cx = drawX + (sprite:getWidth() * scaleX) / 2
            local cy = drawY + (sprite:getHeight() * scaleY) / 2
            love.graphics.draw(sprite, cx, cy, (e.krot or 0), scaleX, scaleY, sprite:getWidth()/2, sprite:getHeight()/2)
            -- White flash overlay using shader + strong bloom via moonshine glow
            if e.hitFlashTime and e.hitFlashTime > 0 then
                local dur = Config.ENEMY.HIT_FLASH_DURATION or 0.12
                local tnorm = math.min(1, e.hitFlashTime / math.max(0.0001, dur))
                -- white flash amount ramps with remaining time
                self.whitenShader:send('amount', 0.85 * tnorm + 0.15)
                -- Draw additive white flash with bloom chain
                self.hitGlow(function()
                    love.graphics.setBlendMode('add')
                    local prevShader = love.graphics.getShader()
                    love.graphics.setShader(self.whitenShader)
                    love.graphics.draw(sprite, cx, cy, (e.krot or 0), scaleX, scaleY, sprite:getWidth()/2, sprite:getHeight()/2)
                    love.graphics.setShader(prevShader)
                    love.graphics.setBlendMode('alpha')
                end)
            end

            -- Mini HP bar when damaged
            if e.hp < e.maxHp then
                local barCfg = Config.ENEMY_HP_BAR
                local barWidth = barCfg.WIDTH
                local barHeight = barCfg.HEIGHT
                local percent = e.hp / e.maxHp
                local barX = cx - (barWidth / 2)
                local barY = (drawY - 2) + barCfg.OFFSET_Y
                Theme.drawHealthBar(barX, barY, barWidth, barHeight, percent, barCfg.BG_COLOR, barCfg.FG_COLOR, barCfg.CORNER_RADIUS)
            end
        else
            love.graphics.setColor(1, 0.2, 0.2, 1)
            local size = (tileSize - 16) * 0.6
            love.graphics.rectangle('fill', x + (tileSize - size)/2, y + (tileSize - size)/2, size, size)
            love.graphics.setColor(1, 1, 1, 1)
        end
    end
    -- draw floating damage numbers on top
    for _, f in ipairs(self.floaters) do
        local t = math.min(1, f.age / (f.life or 0.3))
        -- along-direction motion with hold at peak
        local life = (f.life or 0.3)
        local holdFrac = 0
        if (f.holdSec or 0) > 0 and life > 0 then
            holdFrac = math.max(0, math.min(0.9, (f.holdSec or 0) / life))
        end
        local tPeakStart = 0.5 - holdFrac * 0.5
        local tPeakEnd = 0.5 + holdFrac * 0.5
        local alongFactor
        if t <= tPeakStart then
            local denom = (tPeakStart > 0 and tPeakStart or 1)
            local a = t / denom
            alongFactor = math.sin((math.pi * 0.5) * a) -- 0..1 forward ease
        elseif t < tPeakEnd then
            alongFactor = 1
        else
            local denom = (1 - tPeakEnd)
            if denom <= 0 then
                alongFactor = 0
            else
                local a = (t - tPeakEnd) / denom
                local endF = (f.endFactor or 0.35)
                -- ease from 1 down to endFactor (not all the way back)
                alongFactor = 1 - (1 - endF) * math.sin((math.pi * 0.5) * a)
            end
        end
        local along = (f.amp or 14) * alongFactor
        local lift = 10 * t
        local x = originX + (f.baseX or 0) + (f.dirX or 0) * along
        local y = originY + (f.baseY or 0) + (f.dirY or 0) * along - lift
        -- scale bounce for pop
        local baseScale = f.isCrit and 1.15 or 1.0
        local scale = baseScale + 0.08 * (1 - t) * math.sin(t * math.pi * 2)
        -- keep full opacity until the last fraction, then fade quickly
        local fadeStart = 0.75 -- start fade a bit earlier for a slightly longer fade time
        local alpha
        if t < fadeStart then
            alpha = 1
        else
            alpha = 1 - (t - fadeStart) / (1 - fadeStart)
        end
        local txt = f.text
        -- hard drop shadow behind text
        local shadowOffset = 2
        love.graphics.setColor(0, 0, 0, alpha)
        love.graphics.setFont(Theme.FONTS.LARGE)
        love.graphics.print(txt, x + shadowOffset, y + shadowOffset, 0, scale, scale)
        -- bold effect via multi-pass prints (white on top)
        if f.isCrit then
            -- EED080
            love.graphics.setColor(0.933, 0.816, 0.502, alpha)
        else
            love.graphics.setColor(1, 1, 1, alpha)
        end
        love.graphics.print(txt, x,   y, 0, scale, scale)
        love.graphics.print(txt, x+1, y, 0, scale, scale)
        love.graphics.print(txt, x, y+1, 0, scale, scale)
        love.graphics.print(txt, x+1, y+1, 0, scale, scale)
    end
end

function EnemySpawnManager:getEnemies()
    return self.enemies
end

function EnemySpawnManager:getCoreHealth()
    return self.coreHealth
end

return EnemySpawnManager


