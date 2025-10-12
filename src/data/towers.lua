-- towers.lua - Per-tower stats and level definitions

local towers = {}

-- Define tower families and their levels
towers.defs = {
	crossbow = {
			upgradeCost = {
				[2] = 10
			},
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
				fireCooldown = 1.2, -- seconds between shots (slightly faster)
				rangePx = 150 -- pixels
				},
				[2] = {
					name = 'Crossbow Turret',
					damageMin = 18,
					damageMax = 28,
					critDamageMin = 36,
					critDamageMax = 56,
					critChance = 0.2,
					fireCooldown = 1.0,
					rangePx = 170
				}
		}
	},
	-- New Fire Tower: short range, fast firing, applies burn over time
	fire = {
			upgradeCost = {
				[2] = 10
			},
		levels = {
			[1] = {
				name = 'Fire Tower',
				-- No direct impact damage; burn deals damage (first tick applied on hit)
				damageMin = 0,
				damageMax = 0,
				critDamageMin = 0,
				critDamageMax = 0,
				critChance = 0.0,
				-- Fire cadence and reach
				fireCooldown = 1.0,
				rangePx = 110,       -- short range (about 1.5 tiles)
				projectileSpeedTps = 12, -- slightly faster travel
				projectileMaxDistancePx = 90, -- very short visible streak
				projectileScale = 0.55,
				-- Cone geometry
				coneHalfAngleRad = 0.8,
				-- Burn effect
				burnDamage = 3,
				burnTicks = 5,
				burnTickInterval = 1.0
			},
				[2] = {
					name = 'Fire Tower',
					damageMin = 0, damageMax = 0, critDamageMin = 0, critDamageMax = 0, critChance = 0.0,
					fireCooldown = 0.9,
					rangePx = 130,
					projectileSpeedTps = 13,
					projectileMaxDistancePx = 110,
					projectileScale = 0.58,
					coneHalfAngleRad = 0.8,
					burnDamage = 5,
					burnTicks = 6,
					burnTickInterval = 0.9
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

function towers.getUpgradeCost(towerId, targetLevel)
	local def = towers.defs[towerId]
	if not def or not def.upgradeCost then return nil end
	return def.upgradeCost[targetLevel]
end

function towers.getMaxLevel(towerId)
	local def = towers.defs[towerId]
	if not def or not def.levels then return 1 end
	local maxLevel = 1
	for level, _ in pairs(def.levels) do
		if level > maxLevel then maxLevel = level end
	end
	return maxLevel
end

return towers


