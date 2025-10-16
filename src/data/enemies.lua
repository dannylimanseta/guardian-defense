-- Canonical enemy catalog used by waves and spawners
-- Each entry defines base stats; per-stage/difficulty modifiers may adjust these at runtime

local Enemies = {
	-- Basic enemy used by current prototype visuals
	enemy_1 = {
		id = 'enemy_1',
		name = 'Goblin',
		speedTilesPerSecond = 1.05,
		hp = 60,
		reward = 1,
		-- fraction of tile size to draw sprite at (defaults to 0.6 if absent)
		tileScale = 0.6
	},
	-- Tougher, slower variant
	enemy_2 = {
		id = 'enemy_2',
		name = 'Brute',
		-- moves slower than enemy_1
		speedTilesPerSecond = 0.75,
		hp = 96,
		-- slightly higher reward
		reward = 2,
		-- larger visual size
		tileScale = 0.75
	}
}

return Enemies
