-- TowerManager.lua - manages towers: placement, targeting, firing

local Config = require 'src/config/Config'
local TowerDefs = require 'src/data/towers'
local CrossbowBehavior = require 'src/systems/TowerBehaviors/crossbow'
local FireBehavior = require 'src/systems/TowerBehaviors/fire'

local TowerManager = {}
TowerManager.__index = TowerManager

local function copyTable(src)
    local dst = {}
    for k, v in pairs(src or {}) do
        dst[k] = v
    end
    return dst
end

local function ensureModifierTable(tower)
    tower.modifiers = tower.modifiers or {}
    if tower.modifiers.rangePercent == nil then tower.modifiers.rangePercent = 0 end
    if tower.modifiers.damagePercent == nil then tower.modifiers.damagePercent = 0 end
    if tower.modifiers.rangeStacks == nil then tower.modifiers.rangeStacks = 0 end
    if tower.modifiers.damageStacks == nil then tower.modifiers.damageStacks = 0 end
    return tower.modifiers
end

function TowerManager:getEffectiveStats(tower)
    if not tower then return {} end
    local base = TowerDefs.getStats(tower.towerId or 'crossbow', tower.level or 1)
    local stats = copyTable(base)
    local mods = ensureModifierTable(tower)
    local rangePercent = mods.rangePercent or 0
    local damagePercent = mods.damagePercent or 0
    if stats.rangePx then
        local baseRange = base.rangePx or stats.rangePx
        local bonus = math.ceil(baseRange * rangePercent)
        stats.rangePx = baseRange + bonus
    end
    local function applyDamageField(field)
        if base[field] ~= nil then
            local penalty = math.ceil(base[field] * damagePercent)
            stats[field] = math.max(0, base[field] - penalty)
        end
    end
    applyDamageField('damageMin')
    applyDamageField('damageMax')
    applyDamageField('critDamageMin')
    applyDamageField('critDamageMax')
    applyDamageField('burnDamage')
    return stats
end

local function spawnPoofParticles(t, tileSize)
    local poof = Config.TOWER.SPAWN_POOF or {}
    local originX = (t.x - 0.5) * tileSize
    local originY = (t.y - 0.5) * tileSize
    t.particles = {}
    local num = poof.NUM or 10
    for i = 1, num do
        local life = (poof.LIFE_MIN or 0.3) + math.random() * ((poof.LIFE_MAX or 0.6) - (poof.LIFE_MIN or 0.3))
        local ang = math.random() * math.pi * 2
        local spd = (poof.SPEED_MIN or 40) + math.random() * ((poof.SPEED_MAX or 120) - (poof.SPEED_MIN or 40))
        t.particles[#t.particles + 1] = {
            x = originX,
            y = originY,
            vx = math.cos(ang) * spd,
            vy = math.sin(ang) * spd,
            life = life,
            age = 0,
            size = (poof.SIZE_MIN or 2) + math.random() * ((poof.SIZE_MAX or 6) - (poof.SIZE_MIN or 2))
        }
    end
end

local function updatePoofParticles(t, dt)
    if not t.particles then return end
    local grav = (Config.TOWER.SPAWN_POOF and Config.TOWER.SPAWN_POOF.GRAVITY) or 0
    for i = #t.particles, 1, -1 do
        local p = t.particles[i]
        p.age = p.age + dt
        p.vy = p.vy + grav * dt
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        if p.age >= p.life then table.remove(t.particles, i) end
    end
    if #t.particles == 0 then t.particles = nil end
end

function TowerManager:new()
    local self = setmetatable({}, TowerManager)
    self.towers = {}
    self.towerBaseSprite = nil
    self.towerCrossbowSprite = nil
    self.towerFireSprite = nil
    self.fireParticleSprite = nil
    self.cardHasteSprite = nil
    return self
end

function TowerManager:placeTower(x, y, towerId, level)
    self.towers[#self.towers + 1] = {
        x = x,
        y = y,
        towerId = towerId or 'crossbow',
        level = level or 1,
        cooldown = 0,
        angleCurrent = 0,
        angleTarget = 0,
        recoil = 0,
        acquireTimer = 0,
        targetEnemy = nil,
        spawnT = 0,
        particles = nil,
        spawnPoofDone = false,
        modifiers = {}
    }
end

function TowerManager:upgradeTower(tower, targetLevel)
    if not tower then return false end
    local currentLevel = tower.level or 1
    local desired = targetLevel or (currentLevel + 1)
    if desired <= currentLevel then return false end
    local maxLevel = TowerDefs.getMaxLevel(tower.towerId or 'crossbow') or currentLevel
    if desired > maxLevel then return false end
    local wasLevel = tower.level or 1
    tower.level = desired
    tower.cooldown = math.min(tower.cooldown or 0, TowerDefs.getStats(tower.towerId or 'crossbow', desired).fireCooldown or tower.cooldown)
    tower.modifiers = ensureModifierTable(tower)
    -- Trigger level-up visual pop
    tower.levelUpT = 0
    return true
end

function TowerManager:getTowers()
    return self.towers
end

function TowerManager:getTowerAt(x, y)
    for _, t in ipairs(self.towers) do
        if t.x == x and t.y == y and not t.destroying then return t end
    end
    return nil
end

function TowerManager:destroyTower(tower)
    if not tower then return false end
    if tower.destroying then return false end
    tower.destroying = true
    tower.destroyT = 0
    tower.destroyDuration = 0.45
    tower.destroyOffsetY = 0
    tower.destroyAlpha = 1
    tower.destroyBaseOffsetY = 0
    tower.destroyBaseAlpha = 1
    tower.destroyPoofDone = false
    tower.targetEnemy = nil
    tower.acquireTimer = 0
    tower.emitter = nil
    return true
end

function TowerManager:applyModifiers(tower, modifiers, cardDef)
    if not tower or not modifiers then return false end
    local mods = ensureModifierTable(tower)
    local rangePercent = modifiers.rangePercent or 0
    local damagePercent = modifiers.damagePercent or 0
    if rangePercent == 0 and damagePercent == 0 then return false end
    mods.rangePercent = (mods.rangePercent or 0) + rangePercent
    mods.damagePercent = (mods.damagePercent or 0) + damagePercent
    mods.rangeStacks = (mods.rangeStacks or 0) + 1
    mods.damageStacks = (mods.damageStacks or 0) + ((damagePercent ~= 0) and 1 or 0)
    tower.lastModifiedBy = cardDef and cardDef.id or nil
    tower.lastModifiedAt = love.timer and love.timer.getTime and love.timer.getTime() or nil
    -- Track applied card/buff counts for display in info panel
    tower.appliedBuffs = tower.appliedBuffs or {}
    if cardDef and cardDef.id then
        local key = tostring(cardDef.id)
        local entry = tower.appliedBuffs[key]
        if not entry then
            entry = { name = cardDef.name or key, count = 0 }
            tower.appliedBuffs[key] = entry
        end
        entry.count = (entry.count or 0) + 1
    end
    return mods
end

function TowerManager:applyTowerBuff(tower, payload, cardDef)
    if not tower or not payload then return false end
    tower.buffs = tower.buffs or {}
    if (payload.buff == 'haste') or (payload.multiplier and payload.duration) then
        local mult = payload.multiplier or ((Config.CARD_EFFECTS and Config.CARD_EFFECTS.HASTE and Config.CARD_EFFECTS.HASTE.FIRE_RATE_MULTIPLIER) or 1.5)
        local dur = payload.duration or ((Config.CARD_EFFECTS and Config.CARD_EFFECTS.HASTE and Config.CARD_EFFECTS.HASTE.DURATION_SECONDS) or 6)
        tower.buffs.haste = tower.buffs.haste or {}
        tower.buffs.haste.multiplier = mult
        tower.buffs.haste.duration = dur
        tower.buffs.haste.remaining = dur
        tower.buffs.haste.elapsed = 0
        -- Track in buff list for UI panel
        tower.appliedBuffs = tower.appliedBuffs or {}
        local key = (cardDef and cardDef.id) or 'haste'
        local entry = tower.appliedBuffs[key]
        if not entry then
            entry = { name = (cardDef and cardDef.name) or 'Haste', count = 0, temporary = true }
            tower.appliedBuffs[key] = entry
        end
        entry.count = (entry.count or 0) + 1
        return true
    end
    return false
end

function TowerManager:update(dt, tileSize, enemies, projectiles, enemySpawnManager)
    for _, t in ipairs(self.towers) do
        if t.destroying then
            t.destroyT = (t.destroyT or 0) + dt
            local dur = t.destroyDuration or 0.45
            local progress = math.min(1, t.destroyT / math.max(0.0001, dur))
            t.destroyAlpha = 1 - progress
            t.destroyOffsetY = -(tileSize * 0.6) * progress
            t.destroyBaseOffsetY = -(tileSize * 0.35) * progress
            t.destroyBaseAlpha = 1 - progress
            if not t.destroyPoofDone then
                t.destroyPoofDone = true
                spawnPoofParticles(t, tileSize)
            end
            updatePoofParticles(t, dt)
            goto continue
        end
        -- spawn anim timer
        t.spawnT = math.min((t.spawnT or 0) + dt, (Config.TOWER.SPAWN_ANIM and Config.TOWER.SPAWN_ANIM.DURATION) or 0)
        -- Haste: scale logical delta time for cooldown and emitter timing
        local timeScale = 1
        if t.buffs and t.buffs.haste and (t.buffs.haste.remaining or 0) > 0 then
            t.buffs.haste.remaining = math.max(0, (t.buffs.haste.remaining or 0) - dt)
            t.buffs.haste.elapsed = math.min((t.buffs.haste.duration or 0), (t.buffs.haste.elapsed or 0) + dt)
            timeScale = t.buffs.haste.multiplier or 1
            if (t.buffs.haste.remaining or 0) <= 0 then
                t.buffs.haste = nil
                timeScale = 1
            end
        end
        local dtLogic = dt * timeScale
        t.cooldown = math.max(0, (t.cooldown or 0) - dtLogic)
        -- Acquire target in range: prioritize closest to core (furthest along path)
        local stats = self:getEffectiveStats(t)
        local best, bestPriority
        for _, e in ipairs(enemies) do
            local a = e.path[math.max(1, e.pathIndex)]
            local b = e.path[math.min(#e.path, e.pathIndex + 1)] or a
            local ax = (a.x - 0.5) * tileSize
            local ay = (a.y - 0.5) * tileSize
            local bx = (b.x - 0.5) * tileSize
            local by = (b.y - 0.5) * tileSize
            local ex = ax + (bx - ax) * (e.progress or 0)
            local ey = ay + (by - ay) * (e.progress or 0)
            local tx = (t.x - 0.5) * tileSize
            local ty = (t.y - 0.5) * tileSize
            local dx = ex - tx
            local dy = ey - ty
            local dist2 = dx*dx + dy*dy
            local maxRange = (stats.rangePx or (Config.TOWER.RANGE_TILES * tileSize))
            if dist2 <= maxRange*maxRange then
                -- Compute fraction of path completed toward core (0..1)
                local pathLen = #e.path or 1
                local totalSegments = math.max(1, pathLen - 1)
                local currentProgress = math.max(0, (e.pathIndex - 1) + (e.progress or 0))
                local frac = math.max(0, math.min(1, currentProgress / totalSegments))
                -- Higher frac => closer to core
                if bestPriority == nil or frac > bestPriority then
                    best = { ex = ex, ey = ey, enemy = e }
                    bestPriority = frac
                end
            end
        end
        if best then
            t.angleTarget = math.atan2(best.ey - (t.y - 0.5) * tileSize, best.ex - (t.x - 0.5) * tileSize)
            if t.targetEnemy ~= best.enemy then
                t.targetEnemy = best.enemy
                t.acquireTimer = Config.TOWER.FIRE_ACQUIRE_DELAY or 0
            else
                t.acquireTimer = math.max(0, (t.acquireTimer or 0) - dtLogic)
            end
        else
            t.targetEnemy = nil
            t.acquireTimer = 0
        end
        t.angleCurrent = t.angleCurrent or 0
        t.angleTarget = t.angleTarget or t.angleCurrent
        local diff = (t.angleTarget - t.angleCurrent)
        diff = (diff + math.pi) % (2 * math.pi) - math.pi
        local lerp = math.min(Config.TOWER.ROTATE_LERP * dt, 1)
        t.angleCurrent = t.angleCurrent + diff * lerp

        -- Delegate behavior-specific update
        local behavior
        if (t.towerId or 'crossbow') == 'fire' then
            behavior = FireBehavior
        else
            behavior = CrossbowBehavior
        end
        local ctx = {
            tileSize = tileSize,
            enemies = enemies,
            projectiles = projectiles,
            enemySpawnManager = enemySpawnManager
        }
        behavior.update(t, dt, dtLogic, ctx, best, stats)
        -- Generic recoil return
        if t.recoil and t.recoil > 0 then
            t.recoil = math.max(0, t.recoil - (Config.TOWER.RECOIL_RETURN_SPEED or 60) * dt)
        end

        -- spawn poof particles once, after landing (when spawn anim completes)
        local animDur = (Config.TOWER.SPAWN_ANIM and Config.TOWER.SPAWN_ANIM.DURATION) or 0
        if not t.spawnPoofDone and animDur > 0 and (t.spawnT or 0) >= animDur and t.particles == nil then
            t.spawnPoofDone = true
            spawnPoofParticles(t, tileSize)
        end
        -- update particles
        updatePoofParticles(t, dt)
        ::continue::
    end

    for i = #self.towers, 1, -1 do
        local t = self.towers[i]
        if t.destroying and (t.destroyT or 0) >= (t.destroyDuration or 0.45) then
            table.remove(self.towers, i)
        end
    end
end

function TowerManager:draw(gridX, gridY, tileSize)
    if not self.towerBaseSprite then
        local path = string.format('%s/%s', Config.ENTITIES_PATH, 'tower_base_1.png')
        if love.filesystem.getInfo(path) then
            self.towerBaseSprite = love.graphics.newImage(path)
        end
    end
    if not self.towerCrossbowSprite1 then
        local path = string.format('%s/%s', Config.ENTITIES_PATH, 'tower_crossbow_1.png')
        if love.filesystem.getInfo(path) then
            self.towerCrossbowSprite1 = love.graphics.newImage(path)
        end
    end
    if not self.towerCrossbowSprite2 then
        local path = string.format('%s/%s', Config.ENTITIES_PATH, 'tower_crossbow_2.png')
        if love.filesystem.getInfo(path) then
            self.towerCrossbowSprite2 = love.graphics.newImage(path)
        end
    end
    if not self.towerFireSprite then
        local path = string.format('%s/%s', Config.ENTITIES_PATH, 'tower_fire_1.png')
        if love.filesystem.getInfo(path) then
            self.towerFireSprite = love.graphics.newImage(path)
        end
    end
    if not self.towerFireSprite2 then
        local path = string.format('%s/%s', Config.ENTITIES_PATH, 'tower_fire_2.png')
        if love.filesystem.getInfo(path) then
            self.towerFireSprite2 = love.graphics.newImage(path)
        end
    end
    if not self.fireParticleSprite then
        local path = string.format('%s/%s', Config.ENTITIES_PATH, 'projectile_fire_1.png')
        if love.filesystem.getInfo(path) then
            self.fireParticleSprite = love.graphics.newImage(path)
        end
    end

    for _, t in ipairs(self.towers) do
        local tileX = gridX + (t.x - 1) * tileSize
        local tileY = gridY + (t.y - 1) * tileSize

        -- spawn anim transforms
        local alpha = 1
        local oy = 0
        local scale = 1
        local dur = (Config.TOWER.SPAWN_ANIM and Config.TOWER.SPAWN_ANIM.DURATION) or 0
        if dur > 0 and (t.spawnT or 0) < dur then
            local u = (t.spawnT or 0) / dur
            alpha = u
            local slide = (Config.TOWER.SPAWN_ANIM.SLIDE_PIXELS or 24)
            oy = -slide * (1 - u)
            local s = (Config.TOWER.SPAWN_ANIM.BACK_S or 1.4)
            local k = 1 + s
            local back = 1 + (k*u - s) * (u - 1) * (u - 1)
            scale = back
        end

        -- draw poof particles behind sprites
        if t.particles then
            local cfg = Config.TOWER.SPAWN_POOF or {}
            for _, p in ipairs(t.particles) do
                local k = 1 - (p.age / p.life)
                local a = (cfg.START_ALPHA or 0.35) * k + (cfg.END_ALPHA or 0) * (1-k)
                love.graphics.setColor(1,1,1,a)
                love.graphics.circle('fill', gridX + p.x, gridY + p.y, p.size)
            end
        end

        if self.towerBaseSprite then
            local scaleX = tileSize / self.towerBaseSprite:getWidth()
            local scaleY = tileSize / self.towerBaseSprite:getHeight()
            local drawX = tileX + (tileSize - self.towerBaseSprite:getWidth() * scaleX) / 2
            local drawY = tileY + (tileSize - self.towerBaseSprite:getHeight() * scaleY) / 2 + oy + (t.destroyBaseOffsetY or 0) + (Config.TOWER.DRAW_Y_OFFSET or 0)
            love.graphics.setColor(1,1,1,alpha * ((t.destroyBaseAlpha ~= nil) and t.destroyBaseAlpha or 1))
            love.graphics.draw(self.towerBaseSprite, drawX, drawY, 0, scaleX * scale, scaleY * scale)
        end

        local isFire = (t.towerId or 'crossbow') == 'fire'
        local isCrossbow = not isFire
        local turretSprite
        if isFire then
            -- pick sprite by level for fire tower
            local lvl = t.level or 1
            if (lvl and lvl >= 2) and self.towerFireSprite2 then
                turretSprite = self.towerFireSprite2
            else
                turretSprite = self.towerFireSprite
            end
        else
            -- pick sprite by level for crossbow
            local lvl = t.level or 1
            turretSprite = (lvl and lvl >= 2) and (self.towerCrossbowSprite2 or self.towerCrossbowSprite1) or (self.towerCrossbowSprite1)
        end
        local particleSprite = self.fireParticleSprite or turretSprite
        local totalAlpha = alpha * ((t.destroyAlpha ~= nil) and t.destroyAlpha or 1)
        local offsetY = oy + (t.destroyOffsetY or 0)
        -- Behavior pre-draw (e.g., fire cone behind turret)
        do
            local behavior
            if isFire then behavior = FireBehavior else behavior = CrossbowBehavior end
            behavior.preDraw(t, { gridX = gridX, gridY = gridY, tileSize = tileSize, particleSprite = particleSprite })
        end
        if turretSprite then
            local scaleX = tileSize / turretSprite:getWidth()
            local scaleY = tileSize / turretSprite:getHeight()
            local cx = tileX + tileSize / 2
            local cy = tileY + tileSize / 2 + offsetY + (Config.TOWER.DRAW_Y_OFFSET or 0)
            local angle = (t.angleCurrent or 0)
            local recoil = (t.recoil or 0)
            local ox = -math.cos(angle) * recoil
            local oy2 = -math.sin(angle) * recoil
            -- Level-up bounce scale
            local sfx = 1
            if t.levelUpT and (t.levelUpT < ((Config.TOWER.LEVEL_UP_BOUNCE and Config.TOWER.LEVEL_UP_BOUNCE.DURATION) or 0)) then
                local dur = (Config.TOWER.LEVEL_UP_BOUNCE and Config.TOWER.LEVEL_UP_BOUNCE.DURATION) or 0.22
                t.levelUpT = t.levelUpT + (love.timer and love.timer.getDelta and love.timer.getDelta() or 0)
                local u = math.min(1, t.levelUpT / math.max(0.0001, dur))
                local sBack = (Config.TOWER.LEVEL_UP_BOUNCE and Config.TOWER.LEVEL_UP_BOUNCE.BACK_S) or 1.5
                local k = 1 + sBack
                local back = 1 + (k*u - sBack) * (u - 1) * (u - 1)
                sfx = back
            end
            love.graphics.setColor(1,1,1,totalAlpha)
            love.graphics.draw(
                turretSprite,
                cx + ox,
                cy + oy2,
                angle,
                scaleX * scale * sfx,
                scaleY * scale * sfx,
                turretSprite:getWidth() / 2,
                turretSprite:getHeight() / 2
            )
            -- Haste overlay (pulsating) above the tower when active
            if t.buffs and t.buffs.haste then
                if not self.cardHasteSprite then
                    -- Haste overlay icon in cards folder
                    local path = 'assets/images/cards/icon_haste.png'
                    if love.filesystem.getInfo(path) then
                        self.cardHasteSprite = love.graphics.newImage(path)
                    end
                end
                local img = self.cardHasteSprite
                if img then
                    local rem = t.buffs.haste.remaining or 0
                    local durH = t.buffs.haste.duration or 1
                    local el = (t.buffs.haste.elapsed or (durH - rem))
                    local uIn = math.min(1, el / 0.25)
                    local uOut = math.min(1, (rem) / 0.25)
                    local fade = math.min(uIn, uOut)
                    local pulse = 0.5 + 0.5 * math.sin((love.timer and love.timer.getTime and love.timer.getTime() or 0) * 8)
                    local alphaH = 0.7 * fade * (0.7 + 0.3 * pulse)
                    local scaleImg = (tileSize / img:getWidth()) * (0.8 + 0.08 * pulse)
                    local ix = cx
                    local iy = (tileY + tileSize * 0.5 + (t.destroyOffsetY or 0)) - tileSize + 20
                    love.graphics.setColor(1, 1, 1, alphaH)
                    love.graphics.setBlendMode('add')
                    love.graphics.draw(img, ix, iy, 0, scaleImg, scaleImg, img:getWidth()/2, img:getHeight()/2)
                    love.graphics.setBlendMode('alpha')
                end
            end
        end
        -- Behavior post-draw (optional overlays)
        do
            local behavior
            if isFire then behavior = FireBehavior else behavior = CrossbowBehavior end
            behavior.postDraw(t, { gridX = gridX, gridY = gridY, tileSize = tileSize, particleSprite = particleSprite })
        end
    end
    love.graphics.setColor(1,1,1,1)
end

-- Draw a non-interactive preview of a tower (base + turret) at a grid tile
-- Intended for placement previews while dragging a card
function TowerManager:drawPreview(gridX, gridY, tileSize, tileXIdx, tileYIdx, towerId, level, alpha)
    -- lazy-load sprites (same assets as normal draw)
    if not self.towerBaseSprite then
        local path = string.format('%s/%s', Config.ENTITIES_PATH, 'tower_base_1.png')
        if love.filesystem.getInfo(path) then
            self.towerBaseSprite = love.graphics.newImage(path)
        end
    end
    if not self.towerCrossbowSprite1 then
        local path = string.format('%s/%s', Config.ENTITIES_PATH, 'tower_crossbow_1.png')
        if love.filesystem.getInfo(path) then
            self.towerCrossbowSprite1 = love.graphics.newImage(path)
        end
    end
    if not self.towerCrossbowSprite2 then
        local path = string.format('%s/%s', Config.ENTITIES_PATH, 'tower_crossbow_2.png')
        if love.filesystem.getInfo(path) then
            self.towerCrossbowSprite2 = love.graphics.newImage(path)
        end
    end
    if not self.towerFireSprite then
        local path = string.format('%s/%s', Config.ENTITIES_PATH, 'tower_fire_1.png')
        if love.filesystem.getInfo(path) then
            self.towerFireSprite = love.graphics.newImage(path)
        end
    end
    if not self.towerFireSprite2 then
        local path = string.format('%s/%s', Config.ENTITIES_PATH, 'tower_fire_2.png')
        if love.filesystem.getInfo(path) then
            self.towerFireSprite2 = love.graphics.newImage(path)
        end
    end

    local ax = gridX + (tileXIdx - 1) * tileSize
    local ay = gridY + (tileYIdx - 1) * tileSize
    local a = alpha or 0.5
    -- base
    if self.towerBaseSprite then
        local scaleX = tileSize / self.towerBaseSprite:getWidth()
        local scaleY = tileSize / self.towerBaseSprite:getHeight()
        local drawX = ax + (tileSize - self.towerBaseSprite:getWidth() * scaleX) / 2
        local drawY = ay + (tileSize - self.towerBaseSprite:getHeight() * scaleY) / 2 + (Config.TOWER.DRAW_Y_OFFSET or 0)
        love.graphics.setColor(1,1,1,a)
        love.graphics.draw(self.towerBaseSprite, drawX, drawY, 0, scaleX, scaleY)
    end
    -- turret (choose by id + level)
    local turretSprite = nil
    local lvl = level or 1
    if (towerId or 'crossbow') == 'fire' then
        turretSprite = (lvl >= 2) and (self.towerFireSprite2 or self.towerFireSprite) or self.towerFireSprite
    else
        turretSprite = (lvl >= 2) and (self.towerCrossbowSprite2 or self.towerCrossbowSprite1) or self.towerCrossbowSprite1
    end
    if turretSprite then
        local scaleX = tileSize / turretSprite:getWidth()
        local scaleY = tileSize / turretSprite:getHeight()
        local cx = ax + tileSize / 2
        local cy = ay + tileSize / 2 + (Config.TOWER.DRAW_Y_OFFSET or 0)
        love.graphics.setColor(1,1,1,a)
        love.graphics.draw(
            turretSprite,
            cx,
            cy,
            0,
            scaleX,
            scaleY,
            turretSprite:getWidth() / 2,
            turretSprite:getHeight() / 2
        )
    end
    love.graphics.setColor(1,1,1,1)
end

return TowerManager


