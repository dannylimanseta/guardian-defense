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
		},
		-- Wave 4: parallel streams of enemy_1 with a brute kicker
		{
			schedule = {
				T.streamAt(0, 'enemy_1', 6, 1.8, 1, { jitter = 0.2 }),
				T.streamAt(0.5, 'enemy_1', 6, 1.8, 2, { jitter = 0.2 }),
				T.burstAfterEnd(1.0, 'enemy_2', 3, 1.0, 2)
			}
		},
		-- Wave 5: denser goblins, short intermission, then brutes
		{
			schedule = {
				T.burstAt(0, 'enemy_1', 12, 0.35, 1, { jitter = 0.2 }),
				T.burstAfterEnd(0.8, 'enemy_1', 12, 0.35, 2, { jitter = 0.2 }),
				T.burstAfter(1.0, 'enemy_2', 4, 1.0, 1)
			}
		},
		-- Wave 6: early brutes backed by a fast goblin lane
		{
			schedule = {
				T.burstAt(0, 'enemy_2', 6, 0.8, 1, { modifiers = { hp = 1.10 } }),
				T.burstAfter(0.5, 'enemy_1', 12, 0.30, 2, { jitter = 0.3 })
			}
		},
		-- Wave 7: accelerated goblin streams, then sturdier brutes
		{
			schedule = {
				T.streamAt(0, 'enemy_1', 8, 2.2, 1, { jitter = 0.25, modifiers = { speed = 1.05 } }),
				T.streamAt(0, 'enemy_1', 8, 2.2, 2, { jitter = 0.25, modifiers = { speed = 1.05 } }),
				T.burstAfterEnd(0.5, 'enemy_2', 6, 0.70, 1, { modifiers = { hp = 1.15 } })
			}
		},
		-- Wave 8: heavy brute push on both lanes
		{
			schedule = {
				T.burstAt(0, 'enemy_2', 10, 0.65, 1, { jitter = 0.2, modifiers = { hp = 1.20, reward = 1.20 } }),
				T.burstAfterEnd(1.0, 'enemy_2', 10, 0.65, 2, { jitter = 0.2, modifiers = { hp = 1.20, reward = 1.20 } })
			}
		},
		-- Wave 9: wide goblin curtain, then a brute squad
		{
			schedule = {
				T.burstAt(0, 'enemy_1', 16, 0.28, 1, { jitter = 0.35 }),
				T.burstAfter(0.0, 'enemy_1', 16, 0.28, 2, { jitter = 0.35 }),
				T.burstAfterEnd(1.2, 'enemy_2', 8, 0.60, 1, { modifiers = { hp = 1.25 } })
			}
		},
		-- Wave 10: alternating lane pressure with a brute finisher
		{
			schedule = {
				T.burstAt(0, 'enemy_1', 8, 0.25, 1),
				T.burstAfter(0.5, 'enemy_1', 8, 0.25, 2),
				T.burstAfter(0.5, 'enemy_1', 8, 0.25, 1),
				T.burstAfter(0.5, 'enemy_2', 6, 0.55, 2, { modifiers = { hp = 1.30 } })
			}
		},
		-- Wave 11: endurance streams with quick stragglers and brutes
		{
			schedule = {
				T.streamAt(0, 'enemy_1', 10, 3.0, 1, { jitter = 0.3, modifiers = { speed = 1.10 } }),
				T.streamAt(0.5, 'enemy_1', 10, 3.0, 2, { jitter = 0.3, modifiers = { speed = 1.10 } }),
				T.burstAfterEnd(0.5, 'enemy_2', 10, 0.50, 1, { modifiers = { hp = 1.35, reward = 1.30 } })
			}
		},
		-- Wave 12: tougher brutes, slightly faster pace
		{
			schedule = {
				T.burstAt(0, 'enemy_2', 12, 0.50, 1, { modifiers = { hp = 1.45, speed = 1.05 } }),
				T.burstAfterEnd(0.8, 'enemy_2', 12, 0.50, 2, { modifiers = { hp = 1.45, speed = 1.05 } })
			}
		},
		-- Wave 13: finale — simultaneous lanes, dense goblins and empowered brutes
		{
			schedule = {
				T.burstAt(0, 'enemy_1', 24, 0.22, 1, { jitter = 0.4, modifiers = { speed = 1.15 } }),
				T.burstAfter(0.0, 'enemy_1', 24, 0.22, 2, { jitter = 0.4, modifiers = { speed = 1.15 } }),
				T.burstAfterEnd(1.5, 'enemy_2', 14, 0.45, 1, { modifiers = { hp = 1.60, speed = 1.08, reward = 1.40 } }),
				T.burstAfter(0.6, 'enemy_2', 14, 0.45, 2, { modifiers = { hp = 1.60, speed = 1.08, reward = 1.40 } })
			}
		}
	}
}

