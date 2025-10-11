-- Canonical enemy catalog used by waves and spawners
-- Each entry defines base stats; per-stage/difficulty modifiers may adjust these at runtime

local Enemies = {
	-- Basic enemy used by current prototype visuals
	enemy_1 = {
		id = 'enemy_1',
		name = 'Goblin',
		speedTilesPerSecond = 0.9,
		hp = 48,
		reward = 1
	}
}

return Enemies
