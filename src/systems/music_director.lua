--[[
  Adaptive gameplay BGM: dual streaming Sources, crossfades, hysteresis, danger duck + heartbeat.
]]
local Settings = require("src.systems.settings")
local Layers = require("src.data.music_layers")
local Sfx = require("src.systems.sfx")

local MusicDirector = {}

local slots = {
    { source = nil, path = nil },
    { source = nil, path = nil },
}
local primary = 1 -- 1 or 2: slot holding the main audible loop when not fading
local fading = false
local fadeT = 0
local fadeFrom = 1
local fadeTo = 2

local suspended = true
local needsImmediateEval = false

local stableLevel = "explore"
local candidateLevel = "explore"
local candidateTimer = 0

local pulseTimer = 0

local function rank(level)
    for i, id in ipairs(Layers.levels) do
        if id == level then return i end
    end
    return 1
end

local function pathForLevel(level)
    return Layers.paths[level] or Layers.paths.explore
end

local function stopSlot(i)
    local s = slots[i]
    if s.source then
        s.source:stop()
        s.source = nil
    end
    s.path = nil
end

local function stopAll()
    stopSlot(1)
    stopSlot(2)
    fading = false
end

local function tryLoadStream(path)
    if not path or path == "" then return nil end
    local ok, src = pcall(love.audio.newSource, path, "stream")
    if not ok or not src then return nil end
    src:setLooping(true)
    return src
end

local function computeInstant(snap)
    if snap.introCountdownActive then
        return "explore"
    end
    if snap.bossActive then
        return "boss"
    end
    if snap.anyElite then
        return "elite"
    end
    if snap.roomHasThreat then
        local n = snap.enemyCount or 0
        if n >= Layers.combatHighEnemyCount then
            return "combat_high"
        end
        return "combat"
    end
    return "explore"
end

local function hysteresisStep(dt, instant)
    if instant ~= candidateLevel then
        candidateLevel = instant
        candidateTimer = 0
    else
        candidateTimer = candidateTimer + dt
    end
    local need = rank(instant) > rank(stableLevel) and Layers.hysteresisUp or Layers.hysteresisDown
    if candidateTimer >= need and instant == candidateLevel then
        stableLevel = instant
    end
end

local function jumpToPath(path)
    stopAll()
    local src = tryLoadStream(path)
    if not src then return end
    primary = 1
    slots[1].source = src
    slots[1].path = path
    src:play()
end

local function startFadeTo(path)
    if not path or path == "" then return end
    local curPath = slots[primary].path
    if curPath == path and slots[primary].source and not fading then
        return
    end

    local inactive = primary == 1 and 2 or 1
    stopSlot(inactive)
    local src = tryLoadStream(path)
    if not src then return end
    slots[inactive].source = src
    slots[inactive].path = path
    src:setVolume(0)
    src:play()

    fading = true
    fadeT = 0
    fadeFrom = primary
    fadeTo = inactive
end

local function finishFade(volMul)
    local old = fadeFrom
    stopSlot(old)
    primary = fadeTo
    volMul = volMul or 1
    if slots[primary].source then
        slots[primary].source:setVolume(volMul)
    end
    fading = false
end

local function updateFade(dt, volMul)
    fadeT = fadeT + dt
    local dur = Layers.crossfadeDuration
    local u = dur > 0 and math.min(1, fadeT / dur) or 1
    local smooth = 0.5 - 0.5 * math.cos(math.pi * u)
    local vOut = (1 - smooth) * volMul
    local vIn = smooth * volMul
    local sOut = slots[fadeFrom].source
    local sIn = slots[fadeTo].source
    if sOut then sOut:setVolume(vOut) end
    if sIn then sIn:setVolume(vIn) end
    if u >= 1 then
        finishFade(volMul)
    end
end

local function dangerMul(hpRatio)
    local t = Layers.dangerHpThreshold
    if hpRatio >= t then return 1 end
    -- At 0 HP ratio → stronger duck (0.42 music), at threshold → 1
    return 0.42 + 0.58 * (hpRatio / t)
end

local function heartbeatInterval(hpRatio)
    local t = Layers.dangerHpThreshold
    if hpRatio >= t then return Layers.heartbeatIntervalMax end
    local stress = 1 - (hpRatio / t)
    return Layers.heartbeatIntervalMax - stress * (Layers.heartbeatIntervalMax - Layers.heartbeatIntervalMin)
end

function MusicDirector.onEnterGameplay()
    suspended = false
    needsImmediateEval = true
    stableLevel = "explore"
    candidateLevel = "explore"
    candidateTimer = 0
    pulseTimer = 0
end

function MusicDirector.onLeaveGameplay()
    suspended = true
    stopAll()
    needsImmediateEval = false
end

function MusicDirector.suspendGameplay()
    suspended = true
    stopAll()
end

function MusicDirector.resumeGameplay()
    local wasSuspended = suspended
    suspended = false
    -- Only cold-reload the loop when we actually stopped (e.g. saloon). Level-up overlay leaves streams running.
    if wasSuspended then
        needsImmediateEval = true
    end
    pulseTimer = 0
end

function MusicDirector.update(dt, snap)
    if suspended or not snap then return end

    local musicMul = Settings.getMusicVolumeMul()

    if needsImmediateEval then
        needsImmediateEval = false
        stableLevel = computeInstant(snap)
        candidateLevel = stableLevel
        candidateTimer = 0
        jumpToPath(pathForLevel(stableLevel))
    end

    hysteresisStep(dt, computeInstant(snap))
    local wantPath = pathForLevel(stableLevel)

    if not fading then
        local cur = slots[primary].path
        if cur ~= wantPath then
            startFadeTo(wantPath)
        elseif slots[primary].source and not slots[primary].source:isPlaying() then
            slots[primary].source:play()
        end
    end

    local hpRatio = snap.hpRatio ~= nil and snap.hpRatio or 1
    local dMul = dangerMul(hpRatio)
    local deathMul = 1
    if snap.playerDying and snap.deathDuration and snap.deathDuration > 0 then
        local u = math.min(1, (snap.deathTimer or 0) / snap.deathDuration)
        deathMul = 1 - u
    end
    local pauseMul = snap.paused and 0.82 or 1
    local volMul = musicMul * dMul * deathMul * pauseMul

    if fading then
        updateFade(dt, volMul)
    else
        local s = slots[primary].source
        if s then
            s:setVolume(volMul)
        end
    end

    -- Heartbeat: low HP, alive, not in intro countdown
    if not snap.playerDying and not snap.introCountdownActive and not snap.paused then
        if hpRatio < Layers.dangerHpThreshold then
            pulseTimer = pulseTimer + dt
            local interval = heartbeatInterval(hpRatio)
            if interval > 0 and pulseTimer >= interval then
                pulseTimer = pulseTimer - interval
                local stress = 1 - (hpRatio / Layers.dangerHpThreshold)
                Sfx.play("heartbeat", { volume = 0.12 + 0.38 * stress })
            end
        else
            pulseTimer = 0
        end
    else
        pulseTimer = 0
    end
end

return MusicDirector
