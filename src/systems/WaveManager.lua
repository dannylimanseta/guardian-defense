-- WaveManager.lua - Schedules and starts enemy waves based on data files

local Config = require 'src/config/Config'
local WavesIndex = require 'src/data/waves.index'
local Enemies = require 'src/data/enemies'

local WaveManager = {}
WaveManager.__index = WaveManager

local function shallowMerge(a, b)
    local out = {}
    if a then
        for k, v in pairs(a) do out[k] = v end
    end
    if b then
        for k, v in pairs(b) do out[k] = v end
    end
    return out
end

local function clampMin(x, minv)
    if x == nil then return minv end
    if x < minv then return minv end
    return x
end

function WaveManager:new(stageId, enemySpawnManager)
    local self = setmetatable({}, WaveManager)
    self.stageId = stageId or 'level_1'
    self.enemySpawnManager = enemySpawnManager

    self.stage = WavesIndex[self.stageId] or { waves = {}, intermissionSeconds = 10, autoStartNext = false }

    -- Merge difficulty preset with per-stage multipliers
    local presetName = self.stage.difficultyPreset or (Config.CURRENT_DIFFICULTY or 'normal')
    local preset = (Config.DIFFICULTY_PRESETS and Config.DIFFICULTY_PRESETS[presetName]) or { count = 1, spawnSpeed = 1, hp = 1, speed = 1, reward = 1 }
    self.baseMultipliers = shallowMerge(preset, self.stage.multipliers or {})

    self.activeWaves = {}
    self.nextWaveIndex = 1
    self.intermissionRemaining = 0
    self.pendingShieldClear = {}

    return self
end

local function computeAbsoluteSchedule(events)
    local out = {}
    local prevStart = 0
    local prevEnd = 0
    for i, ev in ipairs(events or {}) do
        local at = 0
        if ev.at ~= nil then
            at = ev.at
        elseif ev.afterEnd ~= nil then
            at = prevEnd + ev.afterEnd
        elseif ev.after ~= nil then
            at = prevStart + ev.after
        else
            at = 0 -- default to absolute 0
        end
        local count = ev.count or 1
        local every = ev.every or 0
        local duration = math.max(0, (count > 0 and (count - 1) or 0) * every)
        prevStart = at
        prevEnd = at + duration
        local evAbs = {}
        for k, v in pairs(ev) do evAbs[k] = v end
        evAbs.at = at
        out[#out + 1] = evAbs
    end
    return out
end

local function buildSpawnersFromSchedule(absSchedule, multipliers)
    local spawners = {}
    for _, ev in ipairs(absSchedule) do
        local baseCount = ev.count or 1
        local finalCount = math.max(0, math.floor(baseCount * (multipliers.count or 1) + 0.0001))
        if finalCount > 0 then
            local interval = (ev.every or 0) * (Config.ENEMY.SPAWN_INTERVAL_MULTIPLIER or 1)
            local speedMul = clampMin(multipliers.spawnSpeed or 1, 0.0001)
            local finalInterval = interval / speedMul
            if finalCount == 1 then
                finalInterval = 0 -- single spawn, no spacing
            end
            local mods = shallowMerge({
                hp = multipliers.hp or 1,
                speed = multipliers.speed or 1,
                reward = multipliers.reward or 1
            }, ev.modifiers or {})

            spawners[#spawners + 1] = {
                enemyId = ev.type or 'enemy_1',
                spawnIndex = ev.spawnIndex or 1,
                jitter = ev.jitter or 0,
                interval = clampMin(finalInterval, 0.01),
                remaining = finalCount,
                nextFireAt = ev.at or 0,
                modifiers = mods
            }
        end
    end
    return spawners
end

function WaveManager:startNextWave()
    local idx = self.nextWaveIndex or 1
    local waveDef = (self.stage.waves or {})[idx]
    if not waveDef then return false end

    local absSchedule = computeAbsoluteSchedule(waveDef.schedule or {})
    local spawners = buildSpawnersFromSchedule(absSchedule, self.baseMultipliers)

    local wave = {
        index = idx,
        name = waveDef.name or ('Wave ' .. tostring(idx)),
        elapsed = 0,
        spawners = spawners,
        done = false
    }
    table.insert(self.activeWaves, wave)

    self.nextWaveIndex = idx + 1
    return true
end

function WaveManager:update(dt)
    -- Update active waves
    for i = #self.activeWaves, 1, -1 do
        local wave = self.activeWaves[i]
        wave.elapsed = wave.elapsed + dt
        local allDone = true
        for j = #wave.spawners, 1, -1 do
            local s = wave.spawners[j]
            if s.remaining > 0 then
                allDone = false
                while s.remaining > 0 and wave.elapsed >= s.nextFireAt do
                    if self.enemySpawnManager and self.enemySpawnManager.requestSpawn then
                        self.enemySpawnManager:requestSpawn(s.enemyId, s.spawnIndex, s.modifiers)
                    end
                    s.remaining = s.remaining - 1
                    local jitterTerm = (s.jitter or 0) * (math.random() - 0.5)
                    s.nextFireAt = s.nextFireAt + s.interval + jitterTerm
                end
            else
                table.remove(wave.spawners, j)
            end
        end
        if allDone or (#wave.spawners == 0) then
            table.remove(self.activeWaves, i)
            -- start intermission if none active and waves remain
            if #self.activeWaves == 0 and (self.nextWaveIndex <= #(self.stage.waves or {})) then
                self.intermissionRemaining = math.max(0, self.stage.intermissionSeconds or 0)
                -- Clear any wave-limited core shield when a wave fully ends and no waves are active
                -- wave ended; clear shields that were applied specifically for that wave once enemies are gone
                if self.enemySpawnManager and self.enemySpawnManager.clearWaveShield then
                    local shouldDefer = false
                    if self.enemySpawnManager.getEnemies then
                        local enemies = self.enemySpawnManager:getEnemies()
                        shouldDefer = (enemies ~= nil and #enemies > 0)
                    end
                    if shouldDefer then
                        self.pendingShieldClear[#self.pendingShieldClear + 1] = wave.index
                    else
                        self.enemySpawnManager:clearWaveShield(wave.index)
                    end
                end
            end
        end
    end

    if self.enemySpawnManager and self.enemySpawnManager.clearWaveShield then
        if self.pendingShieldClear and #self.pendingShieldClear > 0 then
            local enemies = nil
            if self.enemySpawnManager.getEnemies then
                enemies = self.enemySpawnManager:getEnemies()
            end
            if enemies == nil or #enemies == 0 then
                for i = 1, #self.pendingShieldClear do
                    self.enemySpawnManager:clearWaveShield(self.pendingShieldClear[i])
                end
                self.pendingShieldClear = {}
            end
        end
    end

    -- Intermission countdown and auto-start
    if (#self.activeWaves == 0) and (self.nextWaveIndex <= #(self.stage.waves or {})) then
        if self.intermissionRemaining and self.intermissionRemaining > 0 then
            self.intermissionRemaining = math.max(0, self.intermissionRemaining - dt)
            if self.intermissionRemaining == 0 and self.stage.autoStartNext then
                self:startNextWave()
            end
        elseif self.stage.autoStartNext then
            self:startNextWave()
        end
    end
end

function WaveManager:activeWavesCount()
    return #self.activeWaves
end

function WaveManager:areWavesComplete()
    return (self.nextWaveIndex > #(self.stage.waves or {})) and (#self.activeWaves == 0)
end

function WaveManager:getIntermissionRemaining()
    return self.intermissionRemaining or 0
end

function WaveManager:getNextWaveIndex()
    return self.nextWaveIndex or 1
end

function WaveManager:getCurrentWaveIndex()
    if not self.activeWaves or #self.activeWaves == 0 then return nil end
    local wave = self.activeWaves[#self.activeWaves]
    return wave and wave.index or nil
end

return WaveManager
