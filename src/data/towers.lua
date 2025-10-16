-- towers.lua - Per-tower stats and level definitions

local towers = {}

-- Define tower families and their levels
towers.defs = {
	crossbow = {
			upgradeCost = {
				[2] = 15,
				[3] = 27,
				[4] = 42,
				[5] = 63
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
					damageMin = 16,
					damageMax = 26,
					critDamageMin = 32,
					critDamageMax = 50,
					critChance = 0.18,
					fireCooldown = 1.05,
					rangePx = 165
				},
				[3] = {
					name = 'Crossbow Turret',
					damageMin = 20,
					damageMax = 32,
					critDamageMin = 40,
					critDamageMax = 64,
					critChance = 0.20,
					fireCooldown = 0.95,
					rangePx = 180
				},
				[4] = {
					name = 'Crossbow Turret',
					damageMin = 24,
					damageMax = 38,
					critDamageMin = 48,
					critDamageMax = 76,
					critChance = 0.22,
					fireCooldown = 0.9,
					rangePx = 190
				},
				[5] = {
					name = 'Crossbow Turret',
					damageMin = 28,
					damageMax = 44,
					critDamageMin = 56,
					critDamageMax = 88,
					critChance = 0.24,
					fireCooldown = 0.85,
					rangePx = 200
				}
		}
	},
	-- New Fire Tower: short range, fast firing, applies burn over time
	fire = {
			upgradeCost = {
				[2] = 15,
				[3] = 27,
				[4] = 42,
				[5] = 63
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
				rangePx = 100,       -- reduced from 143; base L1 range
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
					fireCooldown = 0.95,
					rangePx = 112,
					projectileSpeedTps = 13,
					projectileMaxDistancePx = 105,
					projectileScale = 0.57,
					coneHalfAngleRad = 0.8,
					burnDamage = 4,
					burnTicks = 5,
					burnTickInterval = 0.95
				},
				[3] = {
					name = 'Fire Tower',
					damageMin = 0, damageMax = 0, critDamageMin = 0, critDamageMax = 0, critChance = 0.0,
					fireCooldown = 0.9,
					rangePx = 124,
					projectileSpeedTps = 14,
					projectileMaxDistancePx = 120,
					projectileScale = 0.6,
					coneHalfAngleRad = 0.8,
					burnDamage = 5,
					burnTicks = 6,
					burnTickInterval = 0.9
				},
				[4] = {
					name = 'Fire Tower',
					damageMin = 0, damageMax = 0, critDamageMin = 0, critDamageMax = 0, critChance = 0.0,
					fireCooldown = 0.85,
					rangePx = 134,
					projectileSpeedTps = 15,
					projectileMaxDistancePx = 130,
					projectileScale = 0.62,
					coneHalfAngleRad = 0.8,
					burnDamage = 6,
					burnTicks = 6,
					burnTickInterval = 0.85
				},
				[5] = {
					name = 'Fire Tower',
					damageMin = 0, damageMax = 0, critDamageMin = 0, critDamageMax = 0, critChance = 0.0,
					fireCooldown = 0.8,
					rangePx = 145,
					projectileSpeedTps = 16,
					projectileMaxDistancePx = 140,
					projectileScale = 0.65,
					coneHalfAngleRad = 0.8,
					burnDamage = 7,
					burnTicks = 7,
					burnTickInterval = 0.8
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


