-- ProjectileManager.lua - updates, draws and collides projectiles

local Config = require 'src/config/Config'

local ProjectileManager = {}
ProjectileManager.__index = ProjectileManager

function ProjectileManager:new()
    local self = setmetatable({}, ProjectileManager)
    self.projectiles = {}
    self.projectileSprite = nil
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
            cache.projectileSprite:setFilter('nearest', 'nearest')
        end
    end
    return cache.projectileSprite
end

function ProjectileManager:update(dt, gridX, gridY, gridWidth, gridHeight, tileSize, enemies, enemySpawnManager, onHitScreenMove)
    for i = #self.projectiles, 1, -1 do
        local p = self.projectiles[i]
        p.x = p.x + math.cos(p.angle) * p.speed * dt
        p.y = p.y + math.sin(p.angle) * p.speed * dt

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
            enemySpawnManager:damageEnemy(hitIndex, p.damage, dx, dy, 1)
            if onHitScreenMove then
                local amp = Config.GAME.SCREEN_HIT_MOVE_AMP
                onHitScreenMove(dx * amp, dy * amp)
            end
            table.remove(self.projectiles, i)
        else
            if p.x < 0 or p.y < 0 or p.x > gridWidth or p.y > gridHeight then
                table.remove(self.projectiles, i)
            end
        end
    end
end

function ProjectileManager:draw(gridX, gridY, tileSize)
    local sprite = getProjectileSprite(self)
    if not sprite then return end
    for _, p in ipairs(self.projectiles) do
        local scale = (tileSize / sprite:getWidth()) * Config.TOWER.PROJECTILE_SCALE
        local drawX = gridX + p.x
        local drawY = gridY + p.y
        love.graphics.draw(sprite, drawX, drawY, p.angle, scale, scale, sprite:getWidth()/2, sprite:getHeight()/2)
    end
end

return ProjectileManager


