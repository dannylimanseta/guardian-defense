-- CardSystem.lua - Central card play/validation and effect registry

local CardSystem = {}

local handlers = {}

function CardSystem.register(typeId, fn)
    handlers[typeId] = fn
end

local function getWaveTag(ctx)
    if not ctx or not ctx.waveManager then return nil end
    if ctx.waveManager.getCurrentWaveIndex then
        local idx = ctx.waveManager:getCurrentWaveIndex()
        if idx ~= nil then return idx end
    end
    if ctx.waveManager.getNextWaveIndex then
        return ctx.waveManager:getNextWaveIndex()
    end
    return nil
end

-- params: { x, y } in game coordinates (optional for non-target cards)
function CardSystem.play(ctx, def, params)
    if not def or not ctx or not ctx.gridMap then return false end
    local handler = handlers[def.type]
    if not handler then return false end
    local target = nil
    if params and params.x and params.y then
        target = ctx.gridMap:getTileAtPosition(params.x, params.y)
    end
    local ok = handler(ctx, def, target)
    return ok and true or false
end

-- Built-in handlers

-- place_tower
CardSystem.register('place_tower', function(ctx, def, tile)
    if not def.payload or not def.payload.tower then return false end
    if not tile then return false end
    -- If dropped on an occupied tile that has the same tower type, treat as upgrade attempt
    if ctx.gridMap:isOccupied(tile.x, tile.y) then
        local tower = ctx.gridMap.towerManager and ctx.gridMap.towerManager:getTowerAt(tile.x, tile.y)
        if tower and (tower.towerId == def.payload.tower) then
            local currentLevel = tower.level or 1
            local targetLevel = currentLevel + 1
            local TowerDefs = require 'src/data/towers'
            local cost = TowerDefs.getUpgradeCost(tower.towerId or 'crossbow', targetLevel) or 0
            if ctx.game and ctx.game.attemptTowerUpgrade then
                return ctx.game:attemptTowerUpgrade(tower, targetLevel, cost, { requireCard = false })
            end
            -- Fallback: allow GridMap callback if accessible
            if ctx.gridMap and ctx.gridMap.onTowerUpgradeRequest then
                return ctx.gridMap.onTowerUpgradeRequest(tower, targetLevel, cost)
            end
            return false
        end
    end
    -- Otherwise, placement onto an empty build spot
    if not ctx.gridMap:isBuildSpot(tile.x, tile.y) then return false end
    if ctx.gridMap:isOccupied(tile.x, tile.y) then return false end
    return ctx.gridMap:placeTowerAt(tile.x, tile.y, def.payload.tower, def.payload.level or 1)
end)

-- modify_tower
CardSystem.register('modify_tower', function(ctx, def, tile)
    if not def.payload or not def.payload.modifiers then return false end
    if not tile then return false end
    if not ctx.gridMap:isOccupied(tile.x, tile.y) then return false end
    return ctx.gridMap:applyTowerModifiers(tile.x, tile.y, def.payload.modifiers, def)
end)

-- apply_tower_buff
CardSystem.register('apply_tower_buff', function(ctx, def, tile)
    if not def.payload then return false end
    if not tile then return false end
    if not ctx.gridMap:isOccupied(tile.x, tile.y) then return false end
    return ctx.gridMap:applyTowerBuff(tile.x, tile.y, def.payload, def)
end)

-- apply_path_effect
CardSystem.register('apply_path_effect', function(ctx, def, tile)
    if not def.payload then return false end
    if not tile then return false end
    if not ctx.gridMap:isPathTile(tile.x, tile.y) then return false end
    if ctx.gridMap:hasPathEffect(tile.x, tile.y) then return false end
    local waveTag = getWaveTag(ctx)
    return ctx.gridMap:applyPathEffect(tile.x, tile.y, def.payload, def, waveTag)
end)

-- apply_core_shield (non-target)
CardSystem.register('apply_core_shield', function(ctx, def, _tile)
    if not def.payload or not def.payload.shieldHp then return false end
    if not ctx.gridMap or not ctx.gridMap.enemySpawnManager then return false end
    local waveTag = getWaveTag(ctx)
    ctx.gridMap.enemySpawnManager:addCoreShield(def.payload.shieldHp, waveTag)
    return true
end)

return CardSystem


