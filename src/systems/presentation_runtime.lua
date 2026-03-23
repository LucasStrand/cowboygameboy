local CombatEvents = require("src.systems.combat_events")
local ImpactFX = require("src.systems.impact_fx")
local Perks = require("src.data.perks")
local PresentationHooks = require("src.data.presentation_hooks")
local Sfx = require("src.systems.sfx")

local PresentationRuntime = {}

local function actorCenter(actor)
    if not actor then
        return nil, nil
    end
    return (actor.x or 0) + (actor.w or 0) * 0.5, (actor.y or 0) + (actor.h or 0) * 0.5
end

local function onProcDamageTaken(payload)
    payload = payload or {}
    local packet = payload.packet or {}
    local metadata = packet.metadata or payload.metadata or {}
    local perk_id = metadata.proc_source_perk_id
    if type(perk_id) ~= "string" then
        return
    end

    local perk = Perks.getById and Perks.getById(perk_id) or nil
    local hooks = perk and perk.presentation_hooks or nil
    local hook_id = hooks and hooks.on_proc or nil
    if type(hook_id) ~= "string" then
        return
    end

    local hook = PresentationHooks.get(hook_id)
    if not hook or hook.event ~= "proc_damage_taken" then
        return
    end

    local x, y = actorCenter(payload.target_actor)
    if not x then
        return
    end

    ImpactFX.spawn(x, y, hook.effect_id, {
        scale_mul = hook.scale_mul or 1,
        tint = hook.tint,
    })
    if hook.sfx_id then
        Sfx.play(hook.sfx_id, { volume = hook.volume or 0.9 })
    end
end

local function resolveLifecycleHook(payload, field, expected_event)
    local hooks = payload and payload.presentation_hooks or nil
    local hook_id = hooks and hooks[field] or nil
    if type(hook_id) ~= "string" then
        return nil
    end
    local hook = PresentationHooks.get(hook_id)
    if not hook or hook.event ~= expected_event then
        return nil
    end
    return hook
end

local function playLifecycleHook(payload, field, expected_event)
    local hook = resolveLifecycleHook(payload, field, expected_event)
    if not hook then
        return
    end
    local x, y = actorCenter(payload.target_actor)
    if not x then
        return
    end
    ImpactFX.spawn(x, y, hook.effect_id, {
        scale_mul = hook.scale_mul or 1,
        tint = hook.tint,
    })
    if hook.sfx_id then
        Sfx.play(hook.sfx_id, { volume = hook.volume or 0.9 })
    end
end

function PresentationRuntime.init()
    CombatEvents.subscribe("OnDamageTaken", onProcDamageTaken)
    CombatEvents.subscribe("OnStatusApplied", function(payload)
        playLifecycleHook(payload, "on_applied", "status_applied")
    end)
    CombatEvents.subscribe("OnStatusRefreshed", function(payload)
        playLifecycleHook(payload, "on_refreshed", "status_refreshed")
    end)
    CombatEvents.subscribe("OnStatusExpired", function(payload)
        playLifecycleHook(payload, "on_expired", "status_expired")
    end)
    CombatEvents.subscribe("OnCleanse", function(payload)
        playLifecycleHook(payload, "on_cleanse", "status_cleanse")
    end)
    CombatEvents.subscribe("OnPurge", function(payload)
        playLifecycleHook(payload, "on_purge", "status_purge")
    end)
    return true
end

return PresentationRuntime
