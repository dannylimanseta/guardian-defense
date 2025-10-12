-- ProjectileManager.lua - updates, draws and collides projectiles

local Config = require 'src/config/Config'

local ProjectileManager = {}
ProjectileManager.__index = ProjectileManager

function ProjectileManager:new()
    local self = setmetatable({}, ProjectileManager)
    self.projectiles = {}
    self.projectileSprite = nil
    self.projectileFireSprite = nil
    -- simple color-cycling for fire using shader multiplicative tint
    self.fireShader = love.graphics.newShader([[ 
        extern number t; // 0..1 cycle
        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 _){
            vec4 px = Texel(tex, tc) * color;
            // gradient: white -> yellow -> orange -> red
            float p = clamp(t, 0.0, 1.0);
            vec3 c1 = vec3(1.0, 1.0, 1.0);
            vec3 c2 = vec3(1.0, 1.0, 0.4);
            vec3 c3 = vec3(1.0, 0.6, 0.2);
            vec3 c4 = vec3(1.0, 0.25, 0.1);
            vec3 c;
            if (p < 0.33) {
                float u = p / 0.33; c = mix(c1, c2, u);
            } else if (p < 0.66) {
                float u = (p - 0.33) / 0.33; c = mix(c2, c3, u);
            } else {
                float u = (p - 0.66) / 0.34; c = mix(c3, c4, u);
            }
            return vec4(c, 1.0) * px; 
        }
    ]])
    return self
end

function ProjectileManager:add(projectile)
    self.projectiles[#self.projectiles + 1] = projectile
end

function ProjectileManager:get()
    return self.projectiles
end

local function getProjectileSprite(cache)
    if not cache.projectileSprite then
        local path = string.format('%s/%s', Config.ENTITIES_PATH, 'projectile_arrow_1.png')
        if love.filesystem.getInfo(path) then
            cache.projectileSprite = love.graphics.newImage(path)
        end
    end
    return cache.projectileSprite
end

local function getFireProjectileSprite(cache)
    if not cache.projectileFireSprite then
        local path = string.format('%s/%s', Config.ENTITIES_PATH, 'projectile_fire_1.png')
        if love.filesystem.getInfo(path) then
            cache.projectileFireSprite = love.graphics.newImage(path)
        end
    end
    return cache.projectileFireSprite
end

function ProjectileManager:update(dt, gridX, gridY, gridWidth, gridHeight, tileSize, enemies, enemySpawnManager, onHitScreenMove)
    for i = #self.projectiles, 1, -1 do
        local p = self.projectiles[i]
        local vx = math.cos(p.angle) * p.speed
        local vy = math.sin(p.angle) * p.speed
        p.x = p.x + vx * dt
        p.y = p.y + vy * dt

        -- Flame visual: spawn spray particles and leave a short trail
        if p.isFireProjectile then
            p.tCycle = ((p.tCycle or 0) + dt * 6) % 1
            -- initialize containers
            if not p.particles then p.particles = {} end
            if not p.trail then p.trail = {} end
            p.emitAcc = (p.emitAcc or 0) + dt * 90 -- particles per second
            while p.emitAcc >= 1 do
                p.emitAcc = p.emitAcc - 1
                local ang = p.angle + (math.random() - 0.5) * 0.6 -- spread cone
                local spd = (tileSize * 2.0) + math.random() * (tileSize * 1.5)
                local life = 0.25 + math.random() * 0.15
                local size = 0.22 + math.random() * 0.25
                p.particles[#p.particles + 1] = {
                    x = p.x,
                    y = p.y,
                    vx = math.cos(ang) * spd,
                    vy = math.sin(ang) * spd,
                    life = life,
                    age = 0,
                    size = size,
                    rot = math.random() * math.pi * 2
                }
            end
            -- age and integrate particles
            for pi = #p.particles, 1, -1 do
                local fp = p.particles[pi]
                fp.age = fp.age + dt
                local damp = 0.9
                fp.vx = fp.vx * (damp ^ (dt * 60))
                fp.vy = fp.vy * (damp ^ (dt * 60)) + (30 * dt) -- slight downward flicker
                fp.x = fp.x + fp.vx * dt
                fp.y = fp.y + fp.vy * dt
                if fp.age >= fp.life then table.remove(p.particles, pi) end
            end
            -- trail samples
            p.trailAcc = (p.trailAcc or 0) + dt
            if p.trailAcc >= 0.02 then
                p.trailAcc = 0
                p.trail[#p.trail + 1] = { x = p.x, y = p.y, age = 0, life = 0.18 }
                if #p.trail > 24 then table.remove(p.trail, 1) end
            end
            for ti = #p.trail, 1, -1 do
                local tpt = p.trail[ti]
                tpt.age = tpt.age + dt
                if tpt.age >= tpt.life then table.remove(p.trail, ti) end
            end
        end

        -- Optional max travel distance for short-range visuals
        local exceededMax = false
        if p.maxDistancePx and p.spawnX and p.spawnY then
            local dx = p.x - p.spawnX
            local dy = p.y - p.spawnY
            if dx*dx + dy*dy > (p.maxDistancePx * p.maxDistancePx) then
                -- clamp visual this frame; mark for removal after collision checks
                p.x = p.spawnX + math.cos(p.angle) * p.maxDistancePx
                p.y = p.spawnY + math.sin(p.angle) * p.maxDistancePx
                exceededMax = true
            end
        else
            p.spawnX = p.spawnX or p.x
            p.spawnY = p.spawnY or p.y
        end

        local hitIndex
        for ei, e in ipairs(enemies) do
            local a = e.path[math.max(1, e.pathIndex)]
            local b = e.path[math.min(#e.path, e.pathIndex + 1)] or a
            local ax = (a.x - 0.5) * tileSize
            local ay = (a.y - 0.5) * tileSize
            local bx = (b.x - 0.5) * tileSize
            local by = (b.y - 0.5) * tileSize
            local exLocal = ax + (bx - ax) * (e.progress or 0)
            local eyLocal = ay + (by - ay) * (e.progress or 0)
            local cx = gridX + exLocal
            local cy = gridY + eyLocal
            local r = tileSize * (Config.TOWER.PROJECTILE_HIT_RADIUS_TILES)
            local dx = (gridX + p.x) - cx
            local dy = (gridY + p.y) - cy
            if dx*dx + dy*dy <= r*r then
                hitIndex = ei
                break
            end
        end
        if hitIndex then
            local tx = p.x
            local ty = p.y
            local a = enemies[hitIndex].path[math.max(1, enemies[hitIndex].pathIndex)]
            local b = enemies[hitIndex].path[math.min(#enemies[hitIndex].path, enemies[hitIndex].pathIndex + 1)] or a
            local ax = (a.x - 0.5) * tileSize
            local ay = (a.y - 0.5) * tileSize
            local bx = (b.x - 0.5) * tileSize
            local by = (b.y - 0.5) * tileSize
            local exLocal = ax + (bx - ax) * (enemies[hitIndex].progress or 0)
            local eyLocal = ay + (by - ay) * (enemies[hitIndex].progress or 0)
            local dx = (exLocal - tx)
            local dy = (eyLocal - ty)
            local len = math.max(0.001, math.sqrt(dx*dx + dy*dy))
            dx, dy = dx/len, dy/len
            -- apply direct hit first (for fire, this is the first tick impact)
            local dmgType = p.isFireProjectile and 'fire' or nil
            enemySpawnManager:damageEnemy(hitIndex, p.damage, dx, dy, 1, p.crit, dmgType)
            -- apply burn if flagged; refreshes on subsequent hits
            if p.isFireProjectile and (p.burnDamage or 0) > 0 and (p.burnTicks or 0) > 0 then
                if enemySpawnManager.applyBurn then
                    enemySpawnManager:applyBurn(hitIndex, p.burnDamage, p.burnTicks, p.burnTickInterval or 0.5)
                end
            end
            if onHitScreenMove then
                local amp = Config.GAME.SCREEN_HIT_MOVE_AMP
                onHitScreenMove(dx * amp, dy * amp)
            end
            table.remove(self.projectiles, i)
        else
            -- if projectile traveled its max distance this frame, remove it now
            if exceededMax then
                table.remove(self.projectiles, i)
            else
                if p.x < 0 or p.y < 0 or p.x > gridWidth or p.y > gridHeight then
                    table.remove(self.projectiles, i)
                end
            end
        end
    end
end

function ProjectileManager:draw(gridX, gridY, tileSize)
    local sprite = getProjectileSprite(self)
    local fireSprite = getFireProjectileSprite(self)
    if not sprite then return end
    for _, p in ipairs(self.projectiles) do
        local isFire = p.isFireProjectile and fireSprite ~= nil
        local useSprite = (isFire and fireSprite) or sprite
        local baseScale = (tileSize / useSprite:getWidth())
        local prjScale = (p.projectileScale or Config.TOWER.PROJECTILE_SCALE)
        local scale = baseScale * prjScale
        local drawX = gridX + p.x
        local drawY = gridY + p.y
        if isFire then
            -- Draw trail with additive blending
            if p.trail then
                love.graphics.setBlendMode('add')
                for _, tpt in ipairs(p.trail) do
                    local u = 1 - math.min(1, tpt.age / (tpt.life or 0.2))
                    local s = scale * (0.7 + 0.6 * u)
                    local cx = gridX + tpt.x
                    local cy = gridY + tpt.y
                    local r, g, b = 1, 0.6 + 0.4 * u, 0.2 + 0.6 * u
                    love.graphics.setColor(r, g, b, 0.35 * u)
                    love.graphics.draw(useSprite, cx, cy, p.angle, s, s, useSprite:getWidth()/2, useSprite:getHeight()/2)
                end
                love.graphics.setBlendMode('alpha')
            end
            -- Draw spray particles with additive blending and hot color
            if p.particles then
                love.graphics.setBlendMode('add')
                for _, fp in ipairs(p.particles) do
                    local u = math.min(1, fp.age / (fp.life or 0.3))
                    -- gradient white->yellow->orange->red
                    local r, g, b
                    if u < 0.33 then
                        local t = u / 0.33; r = 1; g = 1; b = 1 - 0.6 * t
                    elseif u < 0.66 then
                        local t = (u - 0.33) / 0.33; r = 1; g = 1 - 0.4 * t; b = 0.4 - 0.2 * t
                    else
                        local t = (u - 0.66) / 0.34; r = 1; g = 0.6 - 0.35 * t; b = 0.2 - 0.1 * t
                    end
                    local s = scale * (fp.size or 0.3)
                    love.graphics.setColor(r, g, b, 0.9 * (1 - u))
                    love.graphics.draw(useSprite, gridX + fp.x, gridY + fp.y, fp.rot or 0, s, s, useSprite:getWidth()/2, useSprite:getHeight()/2)
                end
                love.graphics.setBlendMode('alpha')
            end
            -- Draw a small hot core sprite at the head
            if self.fireShader then
                local prev = love.graphics.getShader()
                self.fireShader:send('t', p.tCycle or 0)
                love.graphics.setShader(self.fireShader)
                love.graphics.draw(useSprite, drawX, drawY, p.angle, scale * 0.85, scale * 0.85, useSprite:getWidth()/2, useSprite:getHeight()/2)
                love.graphics.setShader(prev)
            else
                love.graphics.draw(useSprite, drawX, drawY, p.angle, scale * 0.85, scale * 0.85, useSprite:getWidth()/2, useSprite:getHeight()/2)
            end
        else
            love.graphics.draw(useSprite, drawX, drawY, p.angle, scale, scale, useSprite:getWidth()/2, useSprite:getHeight()/2)
        end
    end
end

return ProjectileManager


