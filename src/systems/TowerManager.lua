-- TowerManager.lua - manages towers: placement, targeting, firing

local Config = require 'src/config/Config'
local TowerDefs = require 'src/data/towers'

local TowerManager = {}
TowerManager.__index = TowerManager

function TowerManager:new()
    local self = setmetatable({}, TowerManager)
    self.towers = {}
    self.towerBaseSprite = nil
    self.towerCrossbowSprite = nil
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
        spawnPoofDone = false
    }
end

function TowerManager:getTowers()
    return self.towers
end

function TowerManager:getTowerAt(x, y)
    for _, t in ipairs(self.towers) do
        if t.x == x and t.y == y then return t end
    end
    return nil
end

function TowerManager:update(dt, tileSize, enemies, projectiles)
    for _, t in ipairs(self.towers) do
        -- spawn anim timer
        t.spawnT = math.min((t.spawnT or 0) + dt, (Config.TOWER.SPAWN_ANIM and Config.TOWER.SPAWN_ANIM.DURATION) or 0)
        t.cooldown = math.max(0, (t.cooldown or 0) - dt)
        -- Acquire target in range: prioritize closest to core (furthest along path)
        local stats = TowerDefs.getStats(t.towerId or 'crossbow', t.level or 1)
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
            projectiles[#projectiles + 1] = {
                x = px,
                y = py,
                angle = t.angleCurrent,
                speed = Config.TOWER.PROJECTILE_SPEED_TPS * tileSize,
                damage = dmg,
                crit = isCrit,
                alive = true
            }
            t.recoil = (t.recoil or 0) + Config.TOWER.RECOIL_PIXELS
        end
        if t.recoil and t.recoil > 0 then
            t.recoil = math.max(0, t.recoil - Config.TOWER.RECOIL_RETURN_SPEED * dt)
        end

        -- spawn poof particles once, after landing (when spawn anim completes)
        local animDur = (Config.TOWER.SPAWN_ANIM and Config.TOWER.SPAWN_ANIM.DURATION) or 0
        if not t.spawnPoofDone and animDur > 0 and (t.spawnT or 0) >= animDur and t.particles == nil then
            t.spawnPoofDone = true
            t.particles = {}
            local poof = Config.TOWER.SPAWN_POOF or {}
            local num = poof.NUM or 10
            for i=1,num do
                local life = (poof.LIFE_MIN or 0.3) + math.random() * ((poof.LIFE_MAX or 0.6) - (poof.LIFE_MIN or 0.3))
                local ang = math.random() * math.pi * 2
                local spd = (poof.SPEED_MIN or 40) + math.random() * ((poof.SPEED_MAX or 120) - (poof.SPEED_MIN or 40))
                t.particles[#t.particles+1] = {
                    x = (t.x - 0.5) * tileSize,
                    y = (t.y - 0.5) * tileSize,
                    vx = math.cos(ang) * spd,
                    vy = math.sin(ang) * spd,
                    life = life,
                    age = 0,
                    size = (poof.SIZE_MIN or 2) + math.random() * ((poof.SIZE_MAX or 6) - (poof.SIZE_MIN or 2))
                }
            end
        end
        -- update particles
        if t.particles then
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
        ::continue::
    end
end

function TowerManager:draw(gridX, gridY, tileSize)
    if not self.towerBaseSprite then
        local path = string.format('%s/%s', Config.ENTITIES_PATH, 'tower_base_1.png')
        if love.filesystem.getInfo(path) then
            self.towerBaseSprite = love.graphics.newImage(path)
            self.towerBaseSprite:setFilter('nearest', 'nearest')
        end
    end
    if not self.towerCrossbowSprite then
        local path = string.format('%s/%s', Config.ENTITIES_PATH, 'tower_crossbow_1.png')
        if love.filesystem.getInfo(path) then
            self.towerCrossbowSprite = love.graphics.newImage(path)
            self.towerCrossbowSprite:setFilter('nearest', 'nearest')
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
            local drawY = tileY + (tileSize - self.towerBaseSprite:getHeight() * scaleY) / 2 + oy
            love.graphics.setColor(1,1,1,alpha)
            love.graphics.draw(self.towerBaseSprite, drawX, drawY, 0, scaleX * scale, scaleY * scale)
        end

        if self.towerCrossbowSprite then
            local scaleX = tileSize / self.towerCrossbowSprite:getWidth()
            local scaleY = tileSize / self.towerCrossbowSprite:getHeight()
            local cx = tileX + tileSize / 2
            local cy = tileY + tileSize / 2 + oy
            local angle = (t.angleCurrent or 0)
            local recoil = (t.recoil or 0)
            local ox = -math.cos(angle) * recoil
            local oy2 = -math.sin(angle) * recoil
            love.graphics.setColor(1,1,1,alpha)
            love.graphics.draw(
                self.towerCrossbowSprite,
                cx + ox,
                cy + oy2,
                angle,
                scaleX * scale,
                scaleY * scale,
                self.towerCrossbowSprite:getWidth() / 2,
                self.towerCrossbowSprite:getHeight() / 2
            )
        end
    end
    love.graphics.setColor(1,1,1,1)
end

return TowerManager


