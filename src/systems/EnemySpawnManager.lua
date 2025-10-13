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
    self.coreShieldHp = 0
    self.coreShieldWaveTag = nil
    self.coreShieldVisual = {
        active = false,
        alpha = 0,
        pulse = 0,
        time = 0,
        bounceT = 0
    }
    self.enemySprites = {}
    self.flashChains = {}
    self.floaters = {}
    self.worldOriginX = 0
    self.worldOriginY = 0
    self.worldTileSize = Config.TILE_SIZE
    self.killedEvents = {}
    self.deathBursts = {}
    -- Direct shader fallback for per-sprite white flash
    self.whitenShader = love.graphics.newShader([[
        extern number amount; // 0..1
        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 _){
            vec4 px = Texel(tex, tc) * color;
            vec3 outc = mix(px.rgb, vec3(1.0), clamp(amount, 0.0, 1.0));
            return vec4(outc, px.a);
        }
    ]])
    -- Colorize/tint shader: blends original RGB toward a target tint by amount, preserves alpha
    self.colorizeShader = love.graphics.newShader([[
        extern vec3 tint;
        extern number amount; // 0..1
        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 _){
            vec4 px = Texel(tex, tc);
            float a = px.a * color.a;
            vec3 mixed = mix(px.rgb, tint, clamp(amount, 0.0, 1.0));
            return vec4(mixed, a);
        }
    ]])
    -- PostFX chains for hit bloom
    -- We keep a single chain sized to logical resolution and reuse it per enemy draw call
    self.hitGlow = moonshine(Config.LOGICAL_WIDTH, Config.LOGICAL_HEIGHT, moonshine.effects.glow)
    self.hitGlow.glow.min_luma = Config.ENEMY.HIT_GLOW_MIN_LUMA or 0.0
    self.hitGlow.glow.strength = Config.ENEMY.HIT_GLOW_STRENGTH or 10
    return self
end

-- Optional path effect accessor injected by GridMap
function EnemySpawnManager:setPathEffectAccessor(fn)
    self._pathEffectAccessor = fn
end

function EnemySpawnManager:setWorldParams(originX, originY, tileSize)
    self.worldOriginX = originX or 0
    self.worldOriginY = originY or 0
    self.worldTileSize = tileSize or Config.TILE_SIZE
end

local function computeEnemyWorldPosition(self, enemy)
    if not enemy then return nil end
    local tileSize = self.worldTileSize or Config.TILE_SIZE
    local path = enemy.path
    local progress = math.max(0, math.min(1, enemy.progress or 0))
    local px, py
    if path and #path > 0 then
        local a = path[math.max(1, enemy.pathIndex)]
        local b = path[math.min(#path, enemy.pathIndex + 1)] or a
        local ax = (a.x - 0.5) * tileSize
        local ay = (a.y - 0.5) * tileSize
        local bx = (b.x - 0.5) * tileSize
        local by = (b.y - 0.5) * tileSize
        px = ax + (bx - ax) * progress
        py = ay + (by - ay) * progress
    else
        px = (enemy.gridX - 0.5) * tileSize
        py = (enemy.gridY - 0.5) * tileSize
    end
    px = px + (enemy.kox or 0)
    py = py + (enemy.koy or 0)
    px = px + (self.worldOriginX or 0)
    py = py + (self.worldOriginY or 0)
    return px, py
end

function EnemySpawnManager:enqueueKilledEnemy(enemy)
    if not enemy then return end
    local wx, wy = computeEnemyWorldPosition(self, enemy)
    if not wx or not wy then return end
    local event = {
        enemyId = enemy.enemyId or 'enemy_1',
        worldX = wx,
        worldY = wy
    }
    self.killedEvents[#self.killedEvents + 1] = event
    self:spawnDeathBurst(wx, wy)
end

function EnemySpawnManager:consumeKilledEvents()
    if not self.killedEvents or #self.killedEvents == 0 then return nil end
    local events = self.killedEvents
    self.killedEvents = {}
    return events
end

function EnemySpawnManager:spawnDeathBurst(x, y)
    local burst = {
        x = x,
        y = y,
        age = 0,
        duration = 0.4,
        particles = {}
    }
    local num = 10
    for i = 1, num do
        local angle = math.random() * math.pi * 2
        local speed = 120 + math.random() * 80
        local size = 3 + math.random() * 2
        local lifeScale = 0.7 + math.random() * 0.3
        burst.particles[#burst.particles + 1] = {
            x = x,
            y = y,
            vx = math.cos(angle) * speed,
            vy = math.sin(angle) * speed,
            size = size,
            lifeScale = lifeScale
        }
    end
    self.deathBursts[#self.deathBursts + 1] = burst
end
-- Add temporary shield to Vigil Core (stacks)
function EnemySpawnManager:addCoreShield(amount, waveTag)
    local add = math.max(0, tonumber(amount) or 0)
    if add <= 0 then return end
    self.coreShieldHp = (self.coreShieldHp or 0) + add
    if waveTag ~= nil then
        self.coreShieldWaveTag = waveTag
    elseif self.coreShieldWaveTag == nil then
        -- default to zero to explicitly mark it as wave-agnostic if no tag supplied
        self.coreShieldWaveTag = false
    end
    local vis = self.coreShieldVisual
    if vis then
        vis.active = true
        vis.alpha = 0
        vis.time = 0
        vis.bounceT = 0
        vis.pulse = 0
    end
end

function EnemySpawnManager:getCoreShield()
    return self.coreShieldHp or 0
end

function EnemySpawnManager:clearWaveShield(waveTag)
    local shouldClear = false
    if waveTag == nil then
        shouldClear = true
    elseif self.coreShieldWaveTag == nil then
        -- no tag recorded, treat as belonging to the requested wave
        shouldClear = true
    else
        shouldClear = (self.coreShieldWaveTag == waveTag)
    end

    if not shouldClear then return end

    self.coreShieldHp = 0
    self.coreShieldWaveTag = nil
    if self.coreShieldVisual then
        self.coreShieldVisual.active = false
        self.coreShieldVisual.alpha = 0
    end
end

local function applyCoreHit(self, amount)
    local dmg = math.max(0, amount or 0)
    if dmg <= 0 then return end
    local shield = self.coreShieldHp or 0
    if shield > 0 then
        local absorb = math.min(shield, dmg)
        self.coreShieldHp = shield - absorb
        dmg = dmg - absorb
    end
    if dmg > 0 then
        self.coreHealth = math.max(0, (self.coreHealth or 0) - dmg)
    end
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

local function applySpawnPathOffset(enemy, path)
    if not enemy or not path or #path < 2 then return end
    local base = Config.ENEMY.SPAWN_PATH_OFFSET or 0
    if base <= 0 then return end
    local jitter = Config.ENEMY.SPAWN_PATH_OFFSET_JITTER or 0
    local offset = base
    if jitter and jitter ~= 0 then
        offset = offset + ((math.random() * 2) - 1) * jitter
    end
    offset = math.max(0, math.min(offset, 0.95))
    if offset <= 0 then return end

    local fractional = offset
    local idx = enemy.pathIndex or 1
    while fractional >= 1 and idx < (#path - 1) do
        fractional = fractional - 1
        idx = idx + 1
    end
    enemy.pathIndex = idx
    enemy.progress = fractional
    enemy.gridX = path[idx].x
    enemy.gridY = path[idx].y
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
    -- Add small per-enemy movement speed variability (+/-5%)
    do
        local jitter = (math.random() * 0.1) - 0.05
        speedTps = speedTps * (1 + jitter)
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
        krot = 0, krotVel = 0,
        -- damage over time / effects
        burn = nil, -- { damage, ticksLeft, tickInterval, timeSinceLast } or nil
        chill = nil -- { slowPercent, damage, ticksLeft, tickInterval, timeSinceLast } or nil
    }
    applySpawnPathOffset(enemy, path)
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
    -- Add small per-enemy movement speed variability (+/-5%)
    local spawnJitter = (math.random() * 0.1) - 0.05
    local speedWithJitter = baseSpeed * (1 + spawnJitter)

    -- Enemy state
    local enemy = {
        enemyId = 'enemy_1',
        gridX = spawnPos.x,
        gridY = spawnPos.y,
        path = path,
        pathIndex = 1,
        progress = 0, -- 0..1 along segment
        speedTilesPerSecond = speedWithJitter,
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
    applySpawnPathOffset(enemy, path)
    table.insert(self.enemies, enemy)
    return true
end

function EnemySpawnManager:damageEnemy(index, amount, hitDX, hitDY, hitStrength, isCrit, damageType)
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
        self:enqueueKilledEnemy(e)
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
    -- choose floater color based on source
    local color = nil
    if damageType == 'fire' or damageType == 'burn' then
        color = {0.878, 0.494, 0.490, 1} -- #E07E7D
    end

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
        color = color,
        age = 0,
        life = 0.5
    }
end

function EnemySpawnManager:damageAll(amount)
    for i = #self.enemies, 1, -1 do
        self:damageEnemy(i, amount)
    end
end

-- Apply or refresh a burning status on the target enemy at index.
-- Refresh behavior: resets remaining ticks and interval timer; replaces damage/ticks with new values.
function EnemySpawnManager:applyBurn(index, damagePerTick, ticks, tickInterval)
    local e = self.enemies[index]
    if not e then return end
    local newDamage = math.max(0, math.floor((damagePerTick or 0) + 0.5))
    local newTicks = math.max(0, math.floor((ticks or 0) + 0.5))
    local newInterval = tickInterval or 0.5
    if e.burn then
        -- Refresh behavior without resetting the ticking timer: extend/upgrade burn
        -- Keep timeSinceLast so frequent refreshes (e.g., from multiple towers) don't delay ticks
        e.burn.damage = math.max(e.burn.damage or 0, newDamage)
        e.burn.ticksLeft = math.max(e.burn.ticksLeft or 0, newTicks)
        e.burn.tickInterval = newInterval or (e.burn.tickInterval or 0.5)
        -- do NOT reset timeSinceLast
    else
        e.burn = {
            damage = newDamage,
            ticksLeft = newTicks,
            tickInterval = newInterval,
            timeSinceLast = 0
        }
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
        -- process burn effect (refresh behavior handled by applyBurn)
        if e.burn and (e.hp > 0) then
            e.burn.timeSinceLast = (e.burn.timeSinceLast or 0) + dt
            local interval = e.burn.tickInterval or 0.5
            while e.burn.ticksLeft and e.burn.ticksLeft > 0 and e.burn.timeSinceLast >= interval do
                e.burn.timeSinceLast = e.burn.timeSinceLast - interval
                e.burn.ticksLeft = e.burn.ticksLeft - 1
                -- burn tick damage (mark as burn so floater uses fire color)
                self:damageEnemy(i, e.burn.damage, nil, nil, nil, nil, 'burn')
                -- stop if enemy removed during damage
                if not self.enemies[i] then break end
            end
            if self.enemies[i] then
                e = self.enemies[i]
                if e.burn and e.burn.ticksLeft <= 0 then e.burn = nil end
            else
                goto continue_loop
            end
        end
        -- process chill effect (similar to burn tick cadence; applies optional damage)
        if e and e.chill and (e.hp > 0) then
            e.chill.timeSinceLast = (e.chill.timeSinceLast or 0) + dt
            local intervalC = e.chill.tickInterval or 0.5
            while e.chill.ticksLeft and e.chill.ticksLeft > 0 and e.chill.timeSinceLast >= intervalC do
                e.chill.timeSinceLast = e.chill.timeSinceLast - intervalC
                e.chill.ticksLeft = e.chill.ticksLeft - 1
                local dmg = math.max(0, e.chill.damage or 0)
                if dmg > 0 then
                    self:damageEnemy(i, dmg, nil, nil, nil, nil, 'chill')
                    if not self.enemies[i] then break end
                end
            end
            if not self.enemies[i] then
                goto continue_loop
            else
                e = self.enemies[i]
                -- Clear chill when ticks are exhausted; will be refreshed if on a mist tile during draw/update
                if e.chill and (e.chill.ticksLeft or 0) <= 0 then
                    e.chill = nil
                end
            end
        end

        -- Update chill visual fade in/out regardless of effect presence
        do
            local current = e.chillTint or 0
            local target = (e.chill and (e.chill.slowPercent or 0) > 0) and 1 or 0
            local rateIn = 8 -- per second
            local rateOut = 5 -- per second
            if target > current then
                current = math.min(1, current + rateIn * dt)
            else
                current = math.max(0, current - rateOut * dt)
            end
            e.chillTint = current
        end
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
            -- Reached last node (assume Vigil Core); apply shield absorption first
            applyCoreHit(self, Config.ENEMY.DAMAGE_ON_HIT)
            table.remove(self.enemies, i)
        else
            local a = path[e.pathIndex]
            local b = path[e.pathIndex + 1]
            local segmentTime = 1 / e.speedTilesPerSecond
            -- Apply path-based slow from active chill
            if e.chill and (e.chill.slowPercent or 0) > 0 then
                local slowMul = math.max(0, 1 - (e.chill.slowPercent or 0))
                if slowMul < 1 and slowMul > 0 then
                    segmentTime = segmentTime / slowMul
                end
            end
            e.progress = e.progress + dt / segmentTime
            if e.progress >= 1 then
                e.progress = e.progress - 1
                e.pathIndex = e.pathIndex + 1
                e.gridX = b.x
                e.gridY = b.y
            end
        end
        ::continue_loop::
    end

    -- Update death bursts
    if self.deathBursts and #self.deathBursts > 0 then
        for i = #self.deathBursts, 1, -1 do
            local burst = self.deathBursts[i]
            burst.age = burst.age + dt
            local lifeFrac = burst.age / (burst.duration or 0.4)
            if lifeFrac >= 1 then
                table.remove(self.deathBursts, i)
            else
                local decay = 1 - lifeFrac
                for _, p in ipairs(burst.particles) do
                    p.vx = p.vx * (0.9 + 0.05 * decay)
                    p.vy = p.vy * (0.9 + 0.05 * decay) + 120 * dt
                    p.x = p.x + p.vx * dt
                    p.y = p.y + p.vy * dt
                    p.alpha = decay
                end
            end
        end
    end

    -- update floating damage numbers (age/fade only; position computed analytically on draw)
    for i = #self.floaters, 1, -1 do
        local f = self.floaters[i]
        f.age = f.age + dt
        if f.age >= f.life then table.remove(self.floaters, i) end
    end

    -- Update core shield visual: pulsate, bounce, and fade in/out
    do
        local vis = self.coreShieldVisual
        if vis then
            local hasShield = (self.coreShieldHp or 0) > 0
            -- time accumulators for pulsation/bounce
            vis.time = (vis.time or 0) + dt
            vis.pulse = (vis.pulse or 0) + dt
            vis.bounceT = (vis.bounceT or 0) + dt
            -- fade toward target alpha
            local target = hasShield and 1 or 0
            local inRate = 4   -- alpha per second
            local outRate = 3  -- alpha per second
            vis.alpha = vis.alpha or 0
            if target > vis.alpha then
                vis.alpha = math.min(1, vis.alpha + inRate * dt)
            elseif target < vis.alpha then
                vis.alpha = math.max(0, vis.alpha - outRate * dt)
            end
            -- mark inactive when fully faded
            if not hasShield and (vis.alpha or 0) <= 0 then
                vis.active = false
            end
        end
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
        -- While traversing, apply/refresh chill based on current grid tile path effect (if any)
        if self._pathEffectAccessor then
            local gx = e.gridX
            local gy = e.gridY
            local pe = self._pathEffectAccessor(gx, gy)
            if pe and pe.id == 'bonechill_mist' then
                -- Refresh or apply chill with same stacking/refresh semantics as burn
                local slowPercent = math.max(0, math.min(1, pe.slowPercent or 0))
                local ticks = math.max(0, math.floor((pe.slowTicks or 0) + 0.5))
                local interval = pe.tickInterval or 0.5
                local dmg = math.max(0, math.floor((pe.damagePerTick or 0) + 0.5))
                if e.chill then
                    e.chill.slowPercent = math.max(e.chill.slowPercent or 0, slowPercent)
                    e.chill.damage = math.max(e.chill.damage or 0, dmg)
                    e.chill.ticksLeft = math.max(e.chill.ticksLeft or 0, ticks)
                    e.chill.tickInterval = interval or (e.chill.tickInterval or 0.5)
                    -- do not reset timeSinceLast
                else
                    e.chill = { slowPercent = slowPercent, damage = dmg, ticksLeft = ticks, tickInterval = interval, timeSinceLast = 0 }
                end
            end
        end
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
            local def = (Enemies or {})[e.enemyId or 'enemy_1'] or (Enemies and Enemies['enemy_1']) or {}
            local tileScale = def.tileScale or 0.6
            local scaleX = baseScaleX * tileScale
            local scaleY = baseScaleY * tileScale
            -- center sprite in tile
            local drawX = x + (tileSize - sprite:getWidth() * scaleX) / 2
            local drawY = y + (tileSize - sprite:getHeight() * scaleY) / 2
            local cx = drawX + (sprite:getWidth() * scaleX) / 2
            local cy = drawY + (sprite:getHeight() * scaleY) / 2
            -- Draw base sprite
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(sprite, cx, cy, (e.krot or 0), scaleX, scaleY, sprite:getWidth()/2, sprite:getHeight()/2)
            -- Colorize with shader when chilled so dark sprites visibly tint
            if (e.chillTint or 0) > 0 and self.colorizeShader then
                local prevShader = love.graphics.getShader()
                -- Darker blue tint with fade-in/out amount
                self.colorizeShader:send('tint', {0.10, 0.35, 0.80})
                self.colorizeShader:send('amount', (e.chillTint or 0) * 0.3)
                love.graphics.setShader(self.colorizeShader)
                love.graphics.draw(sprite, cx, cy, (e.krot or 0), scaleX, scaleY, sprite:getWidth()/2, sprite:getHeight()/2)
                love.graphics.setShader(prevShader)
            end
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
            -- small red/orange ember indicator for burning
            if e.burn then
                local t = (e.t or 0) * 8
                local s = 1 + 0.1 * math.sin(t)
                love.graphics.setColor(1, 0.35, 0.15, 0.8)
                love.graphics.circle('fill', cx, drawY - 4, 3 * s)
                love.graphics.setColor(1, 1, 1, 1)
            end
        else
            love.graphics.setColor(1, 0.2, 0.2, 1)
            local size = (tileSize - 16) * 0.6
            love.graphics.rectangle('fill', x + (tileSize - size)/2, y + (tileSize - size)/2, size, size)
            love.graphics.setColor(1, 1, 1, 1)
        end
    end
    -- draw death bursts with moonshine glow
    if self.deathBursts and #self.deathBursts > 0 then
        for _, burst in ipairs(self.deathBursts) do
            local alpha = 1 - (burst.age / (burst.duration or 0.4))
            if alpha > 0 then
                self.hitGlow(function()
                    love.graphics.setBlendMode('add')
                    for _, p in ipairs(burst.particles) do
                        local px = originX + (p.x - (self.worldOriginX or 0))
                        local py = originY + (p.y - (self.worldOriginY or 0))
                        local size = (p.size or 4) * (p.lifeScale or 1)
                        love.graphics.setColor(1, 1, 1, (p.alpha or alpha) * 0.9)
                        love.graphics.circle('fill', px, py, size)
                    end
                    love.graphics.setBlendMode('alpha')
                end)
            end
        end
        love.graphics.setColor(1, 1, 1, 1)
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
            love.graphics.setColor(0.933, 0.816, 0.502, alpha) -- crit yellow
        elseif f.color then
            love.graphics.setColor(f.color[1], f.color[2], f.color[3], alpha)
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


