-- Crossbow tower behavior: target, align, and fire projectiles

local Config = require 'src/config/Config'

local Crossbow = {}

function Crossbow.update(tower, dt, dtLogic, ctx, targetInfo, stats)
    if not tower or not ctx or not stats then return end
    -- Fire when aligned and cooldown elapsed
    if targetInfo and (tower.cooldown or 0) == 0 then
        local alignRad = (Config.TOWER.FIRE_ALIGNMENT_DEG or 0) * math.pi / 180
        local angDiff = ((tower.angleTarget - (tower.angleCurrent or 0)) + math.pi) % (2 * math.pi) - math.pi
        if (tower.acquireTimer or 0) > 0 or math.abs(angDiff) > alignRad then
            return
        end
        tower.cooldown = stats.fireCooldown or Config.TOWER.FIRE_COOLDOWN
        local px = (tower.x - 0.5) * (ctx.tileSize or 1)
        local py = (tower.y - 0.5) * (ctx.tileSize or 1)
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
        local projectileSpeed = (stats.projectileSpeedTps or Config.TOWER.PROJECTILE_SPEED_TPS) * (ctx.tileSize or 1)
        local p = {
            x = px,
            y = py,
            angle = (tower.angleCurrent or 0),
            speed = projectileSpeed,
            damage = dmg,
            crit = isCrit,
            alive = true,
            towerId = (tower.towerId or 'crossbow')
        }
        ctx.projectiles[#ctx.projectiles + 1] = p
        tower.recoil = (tower.recoil or 0) + (Config.TOWER.RECOIL_PIXELS or 0)
    end
    if tower.recoil and tower.recoil > 0 then
        tower.recoil = math.max(0, tower.recoil - (Config.TOWER.RECOIL_RETURN_SPEED or 60) * dt)
    end
end

function Crossbow.preDraw(tower, ctx)
    -- no VFX behind the turret for crossbow
end

function Crossbow.postDraw(tower, ctx)
    -- no overlay beyond generic ones
end

return Crossbow


