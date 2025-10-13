-- Fire tower behavior: continuous cone spray applying burn via EnemySpawnManager

local Config = require 'src/config/Config'
local TowerDefs = require 'src/data/towers'

local Fire = {}

local function ensureEmitter(t)
    t.emitter = t.emitter or { particles = {}, trail = {}, emitAcc = 0, trailAcc = 0 }
    t.fireContactCooldown = t.fireContactCooldown or {}
end

function Fire.update(t, dt, dtLogic, ctx, targetInfo, stats)
    local tileSize = ctx.tileSize or Config.TILE_SIZE
    ensureEmitter(t)
    local enemies = ctx.enemies or {}
    -- emit visual particles when there is a target
    if targetInfo then
        local originX = (t.x - 0.5) * tileSize
        local originY = (t.y - 0.5) * tileSize
        local muzzleOffset = 10
        local px = originX + math.cos(t.angleCurrent or 0) * muzzleOffset
        local py = originY + math.sin(t.angleCurrent or 0) * muzzleOffset
        local emitRate = 120
        t.emitter.emitAcc = (t.emitter.emitAcc or 0) + dtLogic * emitRate
        while t.emitter.emitAcc >= 1 do
            t.emitter.emitAcc = t.emitter.emitAcc - 1
            local spread = 0.5
            local ang = (t.angleCurrent or 0) + (math.random() - 0.4) * spread
            local spd = (tileSize * 2.4) + math.random() * (tileSize * 0.8)
            local life = 0.28 + math.random() * 0.16
            local size = 0.12 + math.random() * 0.14
            t.emitter.particles[#t.emitter.particles + 1] = { x = px, y = py, vx = math.cos(ang) * spd, vy = math.sin(ang) * spd, life = life, age = 0, size = size, rot = math.random() * math.pi * 2 }
        end
        t.emitter.trailAcc = (t.emitter.trailAcc or 0) + dtLogic
        if t.emitter.trailAcc >= 0.02 then
            t.emitter.trailAcc = 0
            t.emitter.trail[#t.emitter.trail + 1] = { x = px, y = py, age = 0, life = 0.18 }
            if #t.emitter.trail > 18 then table.remove(t.emitter.trail, 1) end
        end
    end
    -- update particles
    do
        local originX = (t.x - 0.5) * tileSize
        local originY = (t.y - 0.5) * tileSize
        local visualRange = (stats.rangePx or (Config.TOWER.RANGE_TILES * tileSize)) * 1.0
        for i = #t.emitter.particles, 1, -1 do
            local fp = t.emitter.particles[i]
            fp.age = fp.age + dt
            local damp = 0.95
            fp.vx = fp.vx * (damp ^ (dt * 60))
            fp.vy = fp.vy * (damp ^ (dt * 60)) + (20 * dt)
            fp.x = fp.x + fp.vx * dt
            fp.y = fp.y + fp.vy * dt
            local dxo = fp.x - originX
            local dyo = fp.y - originY
            if dxo*dxo + dyo*dyo > visualRange*visualRange or fp.age >= fp.life then
                table.remove(t.emitter.particles, i)
            end
        end
        for i = #t.emitter.trail, 1, -1 do
            local tp = t.emitter.trail[i]
            tp.age = tp.age + dt
            if tp.age >= tp.life then table.remove(t.emitter.trail, i) end
        end
    end
    -- decrement contact cooldowns
    for eRef, cd in pairs(t.fireContactCooldown) do
        t.fireContactCooldown[eRef] = math.max(0, (cd or 0) - dtLogic)
    end
    -- apply burn to enemies within cone
    if ctx.enemySpawnManager then
        local stats2 = TowerDefs.getStats(t.towerId or 'crossbow', t.level or 1)
        local range = (stats2.rangePx or (Config.TOWER.RANGE_TILES * tileSize))
        local halfAngle = stats2.coneHalfAngleRad or 0.8
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
                    if not e.burn then
                        local nx = math.cos(t.angleCurrent or 0)
                        local ny = math.sin(t.angleCurrent or 0)
                        ctx.enemySpawnManager:damageEnemy(ei, stats2.burnDamage or 0, nx, ny, 0.4, false, 'fire')
                        ctx.enemySpawnManager:applyBurn(ei, stats2.burnDamage or 0, stats2.burnTicks or 0, stats2.burnTickInterval or 0.5)
                        t.fireContactCooldown[e] = stats2.burnTickInterval or 0.5
                    else
                        local cdLeft = t.fireContactCooldown[e]
                        if not cdLeft or cdLeft <= 0 then
                            ctx.enemySpawnManager:applyBurn(ei, stats2.burnDamage or 0, stats2.burnTicks or 0, stats2.burnTickInterval or 0.5)
                            t.fireContactCooldown[e] = stats2.burnTickInterval or 0.5
                        end
                    end
                end
            end
        end
    end
end

function Fire.preDraw(t, ctx)
    -- draw cone spray behind turret
    local img = ctx.particleSprite
    if not img or not t.emitter then return end
    local tileSize = ctx.tileSize or Config.TILE_SIZE
    if t.emitter.trail then
        love.graphics.setBlendMode('add')
        for _, tp in ipairs(t.emitter.trail) do
            local u = 1 - math.min(1, tp.age / (tp.life or 0.26))
            local s = (tileSize / img:getWidth()) * 0.45 * (0.7 + 0.7 * u)
            love.graphics.setColor(1, 1 - 0.8 * (1 - u), 0.15 * (1 - u), 0.5 * u)
            love.graphics.draw(img, ctx.gridX + tp.x, ctx.gridY + tp.y, t.angleCurrent, s, s, img:getWidth()/2, img:getHeight()/2)
        end
        love.graphics.setBlendMode('alpha')
    end
    if t.emitter.particles then
        love.graphics.setBlendMode('add')
        for _, fp in ipairs(t.emitter.particles) do
            local u = math.min(1, fp.age / (fp.life or 0.3))
            local u2 = math.min(1, u * 2.4 + 0.1)
            local r = 1
            local g = 1 - 0.75 * u2
            local b = 0.2 - 0.2 * u2
            local tipBoost = 1 + 1.15 * u2
            local s = (tileSize / img:getWidth()) * 0.5 * (fp.size or 0.3) * tipBoost
            local alpha = 0.95 * (1 - math.min(1, u * 0.7))
            love.graphics.setColor(r, g, b, alpha)
            love.graphics.draw(img, ctx.gridX + fp.x, ctx.gridY + fp.y, fp.rot or 0, s, s, img:getWidth()/2, img:getHeight()/2)
        end
        love.graphics.setBlendMode('alpha')
    end
end

function Fire.postDraw(t, ctx)
    -- haste overlay handled in TowerManager
end

return Fire


