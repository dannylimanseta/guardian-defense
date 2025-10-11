-- Helper constructors for wave schedule items

local T = {}

-- Absolute-time burst: spawns `count` enemies starting at second `t`, spaced by `every` seconds
function T.burstAt(t, enemyId, count, every, spawnIndex, opts)
	return {
		at = t,
		type = enemyId,
		count = count,
		every = every,
		spawnIndex = spawnIndex,
		jitter = opts and opts.jitter or nil,
		modifiers = opts and opts.modifiers or nil
	}
end

-- Relative-time burst: starts `dt` seconds after the previous event starts
function T.burstAfter(dt, enemyId, count, every, spawnIndex, opts)
	return {
		after = dt,
		type = enemyId,
		count = count,
		every = every,
		spawnIndex = spawnIndex,
		jitter = opts and opts.jitter or nil,
		modifiers = opts and opts.modifiers or nil
	}
end

-- Stream helper: specify a duration and rate (enemies/sec); converts to a burst
function T.streamAt(t, enemyId, duration, rate, spawnIndex, opts)
	local count = math.max(0, math.floor((duration or 0) * (rate or 0)))
	local every = (rate and rate > 0) and (1 / rate) or 999999
	return T.burstAt(t, enemyId, count, every, spawnIndex, opts)
end

return T
