local T = require('src.data.waves.templates')

return {
	intermissionSeconds = 12,
	autoStartNext = false, -- manual via SPACE
	difficultyPreset = 'normal',
	multipliers = { count = 1.0, spawnSpeed = 1.0 },

	waves = {
		{
			schedule = {
				T.burstAt(0, 'enemy_1', 1, 0.5, 1),
				T.burstAfter(2, 'enemy_1', 2, 0.25, 1),
				-- fan from second spawn concurrently
					T.burstAt(1.5, 'enemy_1', 3, 0.4, 2, { jitter = 1 })
			}
		},
		{
			schedule = {
				T.burstAt(0, 'enemy_1', 3, 0.35, 1, { jitter = 0.2 }),
				-- start 1.5s after the previous event finishes
				T.burstAfterEnd(1.5, 'enemy_1', 5, 0.2, 2),
				-- occasional brute
				T.burstAfter(1.0, 'enemy_2', 2, 0.8, 1)
			}
		},
		-- New Wave 3 focusing on enemy_2
		{
			schedule = {
				-- opening half: enemy_1 from both spawns
				T.burstAt(0, 'enemy_1', 6, 0.65, 1, { jitter = 0.2 }),
				T.burstAfterEnd(1.2, 'enemy_1', 6, 0.65, 2, { jitter = 0.25 }),
				-- staggered later half: enemy_2 starts slightly later
				T.burstAfterEnd(2.0, 'enemy_2', 6, 0.78, 1, { jitter = 0.18 }),
				T.burstAfterEnd(1.3, 'enemy_2', 6, 0.78, 2, { jitter = 0.18 })
			}
		}
	}
}
