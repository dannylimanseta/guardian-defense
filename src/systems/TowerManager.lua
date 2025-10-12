-- TowerManager.lua - manages towers: placement, targeting, firing

local Config = require 'src/config/Config'
local TowerDefs = require 'src/data/towers'

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
    tower.level = desired
    tower.cooldown = math.min(tower.cooldown or 0, TowerDefs.getStats(tower.towerId or 'crossbow', desired).fireCooldown or tower.cooldown)
    tower.modifiers = ensureModifierTable(tower)
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
    return mods
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
        t.cooldown = math.max(0, (t.cooldown or 0) - dt)
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
                t.acquireTimer = math.max(0, (t.acquireTimer or 0) - dt)
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

        -- Fire Tower: persistent cone spray (no discrete projectiles)
        if (t.towerId or 'crossbow') == 'fire' then
            -- initialize emitter and contact cooldown map
            t.emitter = t.emitter or { particles = {}, trail = {}, emitAcc = 0, trailAcc = 0 }
            t.fireContactCooldown = t.fireContactCooldown or {}
            -- emit visual particles when there is a target
            local hasTarget = best ~= nil
            if hasTarget then
                local originX = (t.x - 0.5) * tileSize
                local originY = (t.y - 0.5) * tileSize
                local muzzleOffset = 10
                local px = originX + math.cos(t.angleCurrent or 0) * muzzleOffset
                local py = originY + math.sin(t.angleCurrent or 0) * muzzleOffset
                local emitRate = 120 -- particles per second
                t.emitter.emitAcc = (t.emitter.emitAcc or 0) + dt * emitRate
                while t.emitter.emitAcc >= 1 do
                    t.emitter.emitAcc = t.emitter.emitAcc - 1
                    local spread = 0.5 -- tighter cone to avoid far strays
                    local ang = (t.angleCurrent or 0) + (math.random() - 0.4) * spread
                    local spd = (tileSize * 2.4) + math.random() * (tileSize * 0.8)
                    local life = 0.28 + math.random() * 0.16
                    local size = 0.12 + math.random() * 0.14
                    t.emitter.particles[#t.emitter.particles + 1] = {
                        x = px,
                        y = py,
                        vx = math.cos(ang) * spd,
                        vy = math.sin(ang) * spd,
                        life = life,
                        age = 0,
                        size = size,
                        rot = math.random() * math.pi * 2
                    }
                end
                t.emitter.trailAcc = (t.emitter.trailAcc or 0) + dt
                if t.emitter.trailAcc >= 0.02 then
                    t.emitter.trailAcc = 0
                    t.emitter.trail[#t.emitter.trail + 1] = { x = px, y = py, age = 0, life = 0.18 }
                    if #t.emitter.trail > 18 then table.remove(t.emitter.trail, 1) end
                end
            end
            -- update particles
            -- clamp/cull particles that drift beyond the visual cone range
            local originX = (t.x - 0.5) * tileSize
            local originY = (t.y - 0.5) * tileSize
            local visualRange = (stats.rangePx or (Config.TOWER.RANGE_TILES * tileSize)) * 1.0
            for i2 = #t.emitter.particles, 1, -1 do
                local fp = t.emitter.particles[i2]
                fp.age = fp.age + dt
                local damp = 0.95
                fp.vx = fp.vx * (damp ^ (dt * 60))
                fp.vy = fp.vy * (damp ^ (dt * 60)) + (20 * dt)
                fp.x = fp.x + fp.vx * dt
                fp.y = fp.y + fp.vy * dt
                -- cull if out of cone range
                local dxo = fp.x - originX
                local dyo = fp.y - originY
                if dxo*dxo + dyo*dyo > visualRange*visualRange then
                    table.remove(t.emitter.particles, i2)
                elseif fp.age >= fp.life then
                    table.remove(t.emitter.particles, i2)
                end
            end
            for i2 = #t.emitter.trail, 1, -1 do
                local tp = t.emitter.trail[i2]
                tp.age = tp.age + dt
                if tp.age >= tp.life then table.remove(t.emitter.trail, i2) end
            end
            
            -- decrement contact cooldowns
            for eRef, cd in pairs(t.fireContactCooldown) do
                t.fireContactCooldown[eRef] = math.max(0, (cd or 0) - dt)
            end
            -- apply burn to enemies within cone
            if enemySpawnManager then
                local stats2 = TowerDefs.getStats(t.towerId or 'crossbow', t.level or 1)
                local range = (stats2.rangePx or (Config.TOWER.RANGE_TILES * tileSize))
                local halfAngle = stats2.coneHalfAngleRad or 0.8 -- default backup
                local originX = (t.x - 0.5) * tileSize
                local originY = (t.y - 0.5) * tileSize
                for ei, e in ipairs(enemies) do
                    local a = e.path[math.max(1, e.pathIndex)]
                    local b = e.path[math.min(#e.path, e.pathIndex + 1)] or a
                    local ax = (a.x - 0.5) * tileSize
                    local ay = (a.y - 0.5) * tileSize
                    local bx = (b.x - 0.5) * tileSize
                    local by = (b.y - 0.5) * tileSize
                    local ex = ax + (bx - ax) * (e.progress or 0)
                    local ey = ay + (by - ay) * (e.progress or 0)
                    local dx = ex - originX
                    local dy = ey - originY
                    local dist2 = dx*dx + dy*dy
                    if dist2 <= range*range then
                        local angTo = math.atan2(dy, dx)
                        local adiff = ((angTo - (t.angleCurrent or 0)) + math.pi) % (2 * math.pi) - math.pi
                        if math.abs(adiff) <= halfAngle then
                            
                            -- first tick damage only if not already burning
                            if not e.burn then
                                local nx = math.cos(t.angleCurrent or 0)
                                local ny = math.sin(t.angleCurrent or 0)
                                enemySpawnManager:damageEnemy(ei, stats2.burnDamage or 0, nx, ny, 0.4, false, 'fire')
                                enemySpawnManager:applyBurn(ei, stats2.burnDamage or 0, stats2.burnTicks or 0, stats2.burnTickInterval or 0.5)
                                t.fireContactCooldown[e] = stats2.burnTickInterval or 0.5
                            else
                                local cdLeft = t.fireContactCooldown[e]
                                if not cdLeft or cdLeft <= 0 then
                                    enemySpawnManager:applyBurn(ei, stats2.burnDamage or 0, stats2.burnTicks or 0, stats2.burnTickInterval or 0.5)
                                    t.fireContactCooldown[e] = stats2.burnTickInterval or 0.5
                                end
                            end
                        end
                    end
                end
            end
            goto continue
        end

        if best and t.cooldown == 0 then
            local alignRad = (Config.TOWER.FIRE_ALIGNMENT_DEG or 0) * math.pi / 180
            local angDiff = ((t.angleTarget - t.angleCurrent) + math.pi) % (2 * math.pi) - math.pi
            if (t.acquireTimer or 0) > 0 or math.abs(angDiff) > alignRad then
                goto continue
            end
            t.cooldown = stats.fireCooldown or Config.TOWER.FIRE_COOLDOWN
            local px = (t.x - 0.5) * tileSize
            local py = (t.y - 0.5) * tileSize
            -- compute projectile damage with crit
            local dmgMin = stats.damageMin or Config.TOWER.PROJECTILE_DAMAGE
            local dmgMax = stats.damageMax or Config.TOWER.PROJECTILE_DAMAGE
            local dmg = dmgMin + math.random() * math.max(0, (dmgMax - dmgMin))
            local critChance = stats.critChance or 0
            local isCrit = false
            if math.random() < critChance then
                isCrit = true
                local cmin = stats.critDamageMin or dmgMin * 2
                local cmax = stats.critDamageMax or dmgMax * 2
                dmg = cmin + math.random() * math.max(0, (cmax - cmin))
            end
            local projectileSpeed = (stats.projectileSpeedTps or Config.TOWER.PROJECTILE_SPEED_TPS) * tileSize
            local p = {
                x = px,
                y = py,
                angle = t.angleCurrent,
                speed = projectileSpeed,
                damage = dmg,
                crit = isCrit,
                alive = true,
                towerId = (t.towerId or 'crossbow')
            }
            -- Fire tower uses burn; pass effect params for projectile manager
            if (t.towerId or 'crossbow') == 'fire' then
                p.isFireProjectile = true
                p.burnDamage = stats.burnDamage or 0
                p.burnTicks = stats.burnTicks or 0
                p.burnTickInterval = stats.burnTickInterval or 0.5
                p.maxDistancePx = stats.projectileMaxDistancePx or (tileSize * 1.5)
                p.projectileScale = stats.projectileScale or Config.TOWER.PROJECTILE_SCALE
            end
            projectiles[#projectiles + 1] = p
            t.recoil = (t.recoil or 0) + Config.TOWER.RECOIL_PIXELS
        end
        if t.recoil and t.recoil > 0 then
            t.recoil = math.max(0, t.recoil - Config.TOWER.RECOIL_RETURN_SPEED * dt)
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
    if not self.towerCrossbowSprite then
        local path = string.format('%s/%s', Config.ENTITIES_PATH, 'tower_crossbow_1.png')
        if love.filesystem.getInfo(path) then
            self.towerCrossbowSprite = love.graphics.newImage(path)
        end
    end
    if not self.towerFireSprite then
        local path = string.format('%s/%s', Config.ENTITIES_PATH, 'tower_fire_1.png')
        if love.filesystem.getInfo(path) then
            self.towerFireSprite = love.graphics.newImage(path)
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
            local drawY = tileY + (tileSize - self.towerBaseSprite:getHeight() * scaleY) / 2 + oy + (t.destroyBaseOffsetY or 0)
            love.graphics.setColor(1,1,1,alpha * ((t.destroyBaseAlpha ~= nil) and t.destroyBaseAlpha or 1))
            love.graphics.draw(self.towerBaseSprite, drawX, drawY, 0, scaleX * scale, scaleY * scale)
        end

        local isFire = (t.towerId or 'crossbow') == 'fire'
        local turretSprite = isFire and self.towerFireSprite or self.towerCrossbowSprite
        local particleSprite = self.fireParticleSprite or turretSprite
        local totalAlpha = alpha * ((t.destroyAlpha ~= nil) and t.destroyAlpha or 1)
        local offsetY = oy + (t.destroyOffsetY or 0)
        if isFire and particleSprite and t.emitter then
            -- Draw the cone spray VFX behind the turret head
            -- trail
            if t.emitter.trail then
                love.graphics.setBlendMode('add')
                for _, tp in ipairs(t.emitter.trail) do
                    local u = 1 - math.min(1, tp.age / (tp.life or 0.26))
                    local s = (tileSize / particleSprite:getWidth()) * 0.45 * (0.7 + 0.7 * u)
                    -- earlier yellow->red fade
                    love.graphics.setColor(1, 1 - 0.8 * (1 - u), 0.15 * (1 - u), 0.5 * u)
                    love.graphics.draw(particleSprite, gridX + tp.x, gridY + tp.y, t.angleCurrent, s, s, particleSprite:getWidth()/2, particleSprite:getHeight()/2)
                end
                love.graphics.setBlendMode('alpha')
            end
            -- particles
            if t.emitter.particles then
                love.graphics.setBlendMode('add')
                for _, fp in ipairs(t.emitter.particles) do
                    local u = math.min(1, fp.age / (fp.life or 0.3))
                    -- shift gradient even earlier: intensify red much sooner
                    local u2 = math.min(1, u * 2.4 + 0.1)
                    local r = 1
                    local g = 1 - 0.75 * u2
                    local b = 0.2 - 0.2 * u2
                    -- increase sprite size 2x baseline and scale near tip
                    local tipBoost = 1 + 1.15 * u2
                    local s = (tileSize / particleSprite:getWidth()) * 0.5 * (fp.size or 0.3) * tipBoost
                    -- fade slower early to make red visible, then ramp out
                    local alpha = 0.95 * (1 - math.min(1, u * 0.7))
                    love.graphics.setColor(r, g, b, alpha)
                    love.graphics.draw(particleSprite, gridX + fp.x, gridY + fp.y, fp.rot or 0, s, s, particleSprite:getWidth()/2, particleSprite:getHeight()/2)
                end
                love.graphics.setBlendMode('alpha')
            end
            
        end
        if turretSprite then
            local scaleX = tileSize / turretSprite:getWidth()
            local scaleY = tileSize / turretSprite:getHeight()
            local cx = tileX + tileSize / 2
            local cy = tileY + tileSize / 2 + offsetY
            local angle = (t.angleCurrent or 0)
            local recoil = (t.recoil or 0)
            local ox = -math.cos(angle) * recoil
            local oy2 = -math.sin(angle) * recoil
            love.graphics.setColor(1,1,1,totalAlpha)
            love.graphics.draw(
                turretSprite,
                cx + ox,
                cy + oy2,
                angle,
                scaleX * scale,
                scaleY * scale,
                turretSprite:getWidth() / 2,
                turretSprite:getHeight() / 2
            )
        end
    end
    love.graphics.setColor(1,1,1,1)
end

return TowerManager


