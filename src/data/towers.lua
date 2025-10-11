-- towers.lua - Per-tower stats and level definitions

local towers = {}

-- Define tower families and their levels
towers.defs = {
	crossbow = {
		levels = {
			[1] = {
				name = 'Crossbow Turret',
				-- Damage ranges
				damageMin = 12,
				damageMax = 20,
				critDamageMin = 24,
				critDamageMax = 40,
				critChance = 0.15, -- 15%
				-- Fire and range
				fireCooldown = 1.5, -- seconds between shots
				rangePx = 150 -- pixels
			}
		}
	}
}

function towers.getStats(towerId, level)
	local def = towers.defs[towerId]
	if not def then return {} end
	local lvl = level or 1
	return (def.levels and def.levels[lvl]) or {}
end

return towers


