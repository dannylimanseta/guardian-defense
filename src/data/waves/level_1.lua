local T = require('src.data.waves.templates')

return {
	intermissionSeconds = 12,
	autoStartNext = false, -- manual via SPACE
	difficultyPreset = 'normal',
	multipliers = { count = 1.0, spawnSpeed = 1.0 },

	waves = {
		{
			name = 'Opening',
			reward = 50,
			schedule = {
				T.burstAt(0, 'enemy_1', 5, 0.5, 1),
				T.burstAfter(2, 'enemy_1', 8, 0.25, 1),
				-- fan from second spawn concurrently
				T.burstAt(1.5, 'enemy_1', 6, 0.4, 2),
			}
		},
		{
			name = 'AfterEnd Demo',
			reward = 60,
			schedule = {
				T.burstAt(0, 'enemy_1', 6, 0.35, 1),
				-- start 1.5s after the previous event finishes
				T.burstAfterEnd(1.5, 'enemy_1', 10, 0.2, 2)
			}
		}
	}
}
