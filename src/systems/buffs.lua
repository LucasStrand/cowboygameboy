-- Modular buff/debuff system.
-- Buffs and debuffs are timed status effects with icons, stat modifiers,
-- and optional tick callbacks.

local Sfx = require("src.systems.sfx")

local Buffs = {}
Buffs.__index = Buffs

---------------------------------------------------------------------------
-- Icon atlas
---------------------------------------------------------------------------
local ICON_DIR_BUFF   = "assets/[VerArc Stash] Basic_Skills_and_Buffs/Buffs/"
local ICON_DIR_DEBUFF = "assets/[VerArc Stash] Basic_Skills_and_Buffs/Debuffs/"

local iconCache = {}

local function getIcon(filename, isBuff)
    if iconCache[filename] then return iconCache[filename] end
    local dir = isBuff and ICON_DIR_BUFF or ICON_DIR_DEBUFF
    local ok, img = pcall(love.graphics.newImage, dir .. filename)
    if ok and img then
        img:setFilter("nearest", "nearest")
        iconCache[filename] = img
        return img
    end
    iconCache[filename] = false
    return false
end

---------------------------------------------------------------------------
-- Buff/debuff definitions registry
---------------------------------------------------------------------------
-- Each definition:
--   id           unique string
--   name         display name
--   icon         filename in Buffs/ or Debuffs/ dir
--   isBuff       true = buff, false = debuff
--   duration     seconds (nil = permanent until removed)
--   maxStacks    max stacks (default 1)
--   statMods     { stat = value } per stack — added to effective stats
--   onApply      function(player, stacks) called when applied
--   onTick       function(player, dt, stacks) called each frame
--   onExpire     function(player) called when effect ends
--   visual       optional { jitter = {amp, freq} or {[1],[2]}, tint = {r,g,b,a} }

local definitions = {}
Buffs._definitions = definitions

function Buffs.define(def)
    assert(def.id, "buff definition needs an id")
    def.maxStacks = def.maxStacks or 1
    def.isBuff = def.isBuff ~= false  -- default to buff
    definitions[def.id] = def
end

function Buffs.getDef(id)
    return definitions[id]
end

---------------------------------------------------------------------------
-- Built-in definitions
---------------------------------------------------------------------------

-- Saloon Monster Energy: icon + timer only — actual move speed is Player.monsterMoveBonus.
Buffs.define({
    id = "speed_boost",
    name = "Caffeinated",
    icon = "swiftness.png",
    isBuff = true,
    duration = 20,
    maxStacks = 5,
})

Buffs.define({
    id = "jitter",
    name = "Jittery",
    icon = "confused.png",
    isBuff = false,
    duration = 12,
    maxStacks = 3,
    -- Stacks add amplitude; base kept low so early drinks are subtle.
    visual = { jitter = { amp = 0.42, freq = 18 } },
})

Buffs.define({
    id = "regen",
    name = "Regeneration",
    icon = "regeneration.png",
    isBuff = true,
    duration = 10,
    maxStacks = 1,
    onTick = function(player, dt, stacks)
        player._regenAccum = (player._regenAccum or 0) + dt
        if player._regenAccum >= 1.0 then
            player._regenAccum = player._regenAccum - 1.0
            player:heal(2 * stacks)
        end
    end,
    onExpire = function(player)
        player._regenAccum = nil
    end,
})

Buffs.define({
    id = "attack_boost",
    name = "Sharpshooter",
    icon = "attack_boost.png",
    isBuff = true,
    duration = 15,
    maxStacks = 3,
    statMods = { damage = 2 },
})

Buffs.define({
    id = "defense_boost",
    name = "Ironhide",
    icon = "defense_boost.png",
    isBuff = true,
    duration = 15,
    maxStacks = 3,
    statMods = { armor = 1 },
})

Buffs.define({
    id = "lucky",
    name = "Lucky",
    icon = "lucky_boost.png",
    isBuff = true,
    duration = 20,
    maxStacks = 1,
    statMods = { critChance = 0.1 },
})

Buffs.define({
    id = "slowed",
    name = "Slowed",
    icon = "slowed.png",
    isBuff = false,
    duration = 5,
    maxStacks = 2,
    statMods = { moveSpeed = -20 },
})

Buffs.define({
    id = "bleeding",
    name = "Bleeding",
    icon = "bleeding.png",
    isBuff = false,
    duration = 6,
    maxStacks = 3,
    onTick = function(player, dt, stacks)
        player._bleedAccum = (player._bleedAccum or 0) + dt
        if player._bleedAccum >= 1.0 then
            player._bleedAccum = player._bleedAccum - 1.0
            player.hp = math.max(1, player.hp - stacks)
        end
    end,
    onExpire = function(player)
        player._bleedAccum = nil
    end,
})

Buffs.define({
    id = "attack_down",
    name = "Weakened",
    icon = "attack_down.png",
    isBuff = false,
    duration = 8,
    maxStacks = 2,
    statMods = { damage = -1 },
})

Buffs.define({
    id = "exp_boost",
    name = "Wisdom",
    icon = "exp_boost.png",
    isBuff = true,
    duration = 30,
    maxStacks = 1,
})

---------------------------------------------------------------------------
-- Active effects manager (lives on a player/entity)
---------------------------------------------------------------------------

--- Create a new active-effects tracker.
function Buffs.newTracker()
    return {
        active = {},   -- { [id] = { stacks, timer, def } }
    }
end

--- Apply a buff/debuff by id to a tracker. Returns true if applied.
function Buffs.apply(tracker, id, stacks)
    local def = definitions[id]
    if not def then return false end
    stacks = stacks or 1

    local existing = tracker.active[id]
    if existing then
        -- Stack or refresh
        existing.stacks = math.min(def.maxStacks, existing.stacks + stacks)
        existing.timer = def.duration or math.huge
    else
        tracker.active[id] = {
            stacks = math.min(def.maxStacks, stacks),
            timer = def.duration or math.huge,
            def = def,
        }
    end
    return true
end

--- Remove a buff/debuff by id.
function Buffs.remove(tracker, id, player)
    local entry = tracker.active[id]
    if entry then
        if entry.def.onExpire and player then
            entry.def.onExpire(player)
        end
        tracker.active[id] = nil
    end
end

--- Clear all effects.
function Buffs.clearAll(tracker, player)
    for id, entry in pairs(tracker.active) do
        if entry.def.onExpire and player then
            entry.def.onExpire(player)
        end
    end
    tracker.active = {}
end

--- Update timers, run tick callbacks. Call each frame.
function Buffs.update(tracker, dt, player)
    local expired = {}
    for id, entry in pairs(tracker.active) do
        -- Tick callback
        if entry.def.onTick and player then
            entry.def.onTick(player, dt, entry.stacks)
        end
        -- Timer countdown
        if entry.timer ~= math.huge then
            entry.timer = entry.timer - dt
            if entry.timer <= 0 then
                expired[#expired + 1] = id
            end
        end
    end
    for _, id in ipairs(expired) do
        Buffs.remove(tracker, id, player)
    end
end

--- Collect total stat modifiers from all active effects.
function Buffs.getStatMods(tracker)
    local mods = {}
    for _, entry in pairs(tracker.active) do
        if entry.def.statMods then
            for stat, val in pairs(entry.def.statMods) do
                mods[stat] = (mods[stat] or 0) + val * entry.stacks
            end
        end
    end
    return mods
end

--- Check if a specific effect is active.
function Buffs.has(tracker, id)
    return tracker.active[id] ~= nil
end

--- Get stacks of a specific effect (0 if not active).
function Buffs.stacks(tracker, id)
    local e = tracker.active[id]
    return e and e.stacks or 0
end

--- Read jitter as { amp, freq } or { [1], [2] } (named keys used by built-in "jitter" debuff).
local function visualJitterAmpFreq(jt)
    if type(jt) ~= "table" then return nil, nil end
    local a = jt[1] or jt.amp
    local f = jt[2] or jt.freq
    if type(a) ~= "number" or a <= 0 then return nil, nil end
    if type(f) ~= "number" or f <= 0 then f = 15 end
    return a, f
end

--- Get combined visual effects from all active effects.
function Buffs.getVisuals(tracker)
    local jitterAmp, jitterFreq = 0, 0
    local tintR, tintG, tintB, tintA = 0, 0, 0, 0
    local hasTint = false
    for _, entry in pairs(tracker.active) do
        if entry.def.visual then
            local v = entry.def.visual
            if v.jitter then
                local ja, jf = visualJitterAmpFreq(v.jitter)
                if ja then
                    local st = entry.stacks or 1
                    jitterAmp = jitterAmp + ja * st
                    jitterFreq = math.max(jitterFreq, jf)
                end
            end
            if v.tint then
                tintR = tintR + v.tint[1]
                tintG = tintG + v.tint[2]
                tintB = tintB + v.tint[3]
                tintA = tintA + (v.tint[4] or 0.15)
                hasTint = true
            end
        end
    end
    return {
        jitterAmp = jitterAmp,
        jitterFreq = jitterFreq,
        tint = hasTint and { tintR, tintG, tintB, tintA } or nil,
    }
end

---------------------------------------------------------------------------
-- HUD drawing — row of active buff/debuff icons
---------------------------------------------------------------------------

--- Draw active effect icons. Buffs on left, debuffs on right.
--- x, y = top-left anchor for the buff icon row.
function Buffs.drawIcons(tracker, x, y, scale)
    scale = scale or 2
    local iconSize = 16 * scale
    local gap = 2
    local bx = x
    local dx = x  -- debuffs will draw separately

    -- Separate into buffs and debuffs
    local buffList, debuffList = {}, {}
    for id, entry in pairs(tracker.active) do
        if entry.def.isBuff then
            buffList[#buffList + 1] = entry
        else
            debuffList[#debuffList + 1] = entry
        end
    end

    -- Draw buffs left-to-right
    for _, entry in ipairs(buffList) do
        local icon = getIcon(entry.def.icon, true)
        if icon then
            -- Flash when about to expire
            local alpha = 1
            if entry.timer < 3 then
                alpha = 0.5 + 0.5 * math.sin(love.timer.getTime() * 8)
            end
            love.graphics.setColor(1, 1, 1, alpha)
            love.graphics.draw(icon, bx, y, 0, scale, scale)
            -- Stack count
            if entry.stacks > 1 then
                love.graphics.setColor(1, 1, 1, alpha)
                love.graphics.print(tostring(entry.stacks), bx + iconSize - 8, y + iconSize - 10)
            end
            -- Duration bar below icon
            if entry.timer ~= math.huge and entry.def.duration then
                local frac = math.max(0, entry.timer / entry.def.duration)
                love.graphics.setColor(0.2, 0.8, 0.2, 0.8 * alpha)
                love.graphics.rectangle("fill", bx, y + iconSize + 1, iconSize * frac, 2)
            end
            bx = bx + iconSize + gap
        end
    end

    -- Draw debuffs after buffs
    for _, entry in ipairs(debuffList) do
        local icon = getIcon(entry.def.icon, false)
        if icon then
            local alpha = 1
            if entry.timer < 3 then
                alpha = 0.5 + 0.5 * math.sin(love.timer.getTime() * 8)
            end
            love.graphics.setColor(1, 1, 1, alpha)
            love.graphics.draw(icon, bx, y, 0, scale, scale)
            if entry.stacks > 1 then
                love.graphics.setColor(1, 1, 1, alpha)
                love.graphics.print(tostring(entry.stacks), bx + iconSize - 8, y + iconSize - 10)
            end
            if entry.timer ~= math.huge and entry.def.duration then
                local frac = math.max(0, entry.timer / entry.def.duration)
                love.graphics.setColor(0.8, 0.2, 0.2, 0.8 * alpha)
                love.graphics.rectangle("fill", bx, y + iconSize + 1, iconSize * frac, 2)
            end
            bx = bx + iconSize + gap
        end
    end

    love.graphics.setColor(1, 1, 1)
end

return Buffs
