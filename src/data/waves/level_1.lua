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
				T.burstAfter(2, 'enemy_1', 8, 0.25, 1)
			}
		}
	}
}
