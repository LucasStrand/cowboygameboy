local CombatEvents = require("src.systems.combat_events")
local DamagePacket = require("src.systems.damage_packet")
local DamageResolver = require("src.systems.damage_resolver")
local Perks = require("src.data.perks")
local SourceRef = require("src.systems.source_ref")

local ProcRuntime = {
    MAX_PROC_DEPTH = 1,
}

local function debugLogProc(message)
    if DEBUG and debugLog then
        debugLog("[proc_runtime] " .. message)
    end
end

local function makeCounterKey(rule, payload)
    local source_ref = payload.source_ref or {}
    local metadata = payload.metadata or {}
    local slot_index = metadata.source_slot_index or "none"
    return table.concat({
        tostring(rule.id or "rule"),
        tostring(source_ref.owner_actor_id or "unknown_actor"),
        tostring(source_ref.owner_source_type or "unknown_type"),
        tostring(source_ref.owner_source_id or "unknown_source"),
        tostring(slot_index),
        tostring(payload.target_id or "unknown_target"),
    }, "|")
end

local function getPlayerProcRules(player)
    local rules = {}
    for _, perk_id in ipairs(player.perks or {}) do
        local perk = Perks.getById and Perks.getById(perk_id) or nil
        for _, rule in ipairs((perk and perk.proc_rules) or {}) do
            rules[#rules + 1] = {
                perk = perk,
                rule = rule,
            }
        end
    end
    return rules
end

local function packetCanEvaluateProcs(payload)
    if not payload or not payload.packet then
        return false
    end
    local packet = payload.packet
    if packet.can_trigger_proc == false then
        return false
    end
    if (packet.proc_depth or 0) >= ProcRuntime.MAX_PROC_DEPTH then
        return false
    end
    return true
end

local function ruleMatchesPayload(rule, payload)
    if rule.trigger ~= payload.event_name then
        return false
    end
    if rule.source_owner_type and rule.source_owner_type ~= (payload.source_ref and payload.source_ref.owner_source_type) then
        return false
    end
    if rule.packet_kind and rule.packet_kind ~= payload.packet_kind then
        return false
    end
    if rule.source_actor_kind and rule.source_actor_kind ~= payload.source_actor_kind then
        return false
    end
    return true
end

local function buildProcPacket(entry, payload, proc_damage)
    local source_ref = payload.source_ref or {}
    local proc_rule_id = entry.rule.id or "proc_rule"
    return DamagePacket.new({
        kind = "delayed_secondary_hit",
        family = entry.rule.effect.family or "true",
        base_min = proc_damage,
        base_max = proc_damage,
        can_crit = entry.rule.effect.can_crit == true,
        counts_as_hit = entry.rule.effect.counts_as_hit == true,
        can_trigger_on_hit = entry.rule.effect.can_trigger_on_hit == true,
        can_trigger_proc = entry.rule.effect.can_trigger_proc == true,
        can_lifesteal = entry.rule.effect.can_lifesteal == true,
        snapshots = true,
        proc_depth = (payload.packet.proc_depth or 0) + 1,
        source = SourceRef.new({
            owner_actor_id = source_ref.owner_actor_id,
            owner_source_type = "perk",
            owner_source_id = entry.perk.id,
            parent_source_id = source_ref.owner_source_id,
        }),
        tags = { "proc", "delayed", "true_damage", proc_rule_id },
        target_id = payload.target_id,
        snapshot_data = {
            source_context = {
                base_min = proc_damage,
                base_max = proc_damage,
                damage = 1,
                physical_damage = 0,
                magical_damage = 0,
                true_damage = 0,
                crit_chance = 0,
                crit_damage = 1.5,
                armor_pen = 0,
                magic_pen = 0,
            },
        },
        metadata = {
            proc_rule_id = proc_rule_id,
            proc_source_perk_id = entry.perk.id,
            source_context_kind = "player_weapon_proc",
        },
    })
end

local function queueEveryNthHit(entry, state, payload)
    local pre_defense = payload.pre_defense_damage or 0
    local effect = entry.rule.effect or {}
    local scaled_damage = math.max(
        effect.min_damage or 1,
        math.floor(pre_defense * (effect.damage_scale or 0))
    )
    local packet = buildProcPacket(entry, payload, scaled_damage)
    DamageResolver.enqueueSecondaryJob({
        delay = effect.delay or 0.08,
        packet = packet,
        source_actor = state.player,
        target_selector = "actor_id",
        target_id = payload.target_id,
        target_kind = payload.target_kind,
    })
    debugLogProc(string.format(
        "queued %s on target=%s damage=%s depth=%s",
        tostring(entry.rule.id),
        tostring(payload.target_id),
        tostring(scaled_damage),
        tostring(packet.proc_depth)
    ))
end

local function handleOnHit(state, payload)
    if not packetCanEvaluateProcs(payload) then
        return
    end
    if not state.player or not payload.source_ref or payload.source_ref.owner_actor_id ~= state.player.actorId then
        return
    end

    for _, entry in ipairs(getPlayerProcRules(state.player)) do
        local rule = entry.rule
        if ruleMatchesPayload(rule, payload) and rule.counter and rule.counter.mode == "source_target_hits" then
            local key = makeCounterKey(rule, payload)
            local count = (state.counters[key] or 0) + 1
            state.counters[key] = count
            debugLogProc(string.format(
                "counter %s source=%s target=%s count=%d",
                tostring(rule.id),
                tostring(payload.source_ref.owner_source_id),
                tostring(payload.target_id),
                count
            ))
            if count >= (rule.counter.every_n or 1) then
                state.counters[key] = 0
                if rule.effect and rule.effect.type == "delayed_damage" then
                    queueEveryNthHit(entry, state, payload)
                end
            end
        end
    end
end

function ProcRuntime.init(player)
    local state = {
        player = player,
        counters = {},
    }
    CombatEvents.subscribe("OnHit", function(payload)
        payload = payload or {}
        payload.event_name = "OnHit"
        handleOnHit(state, payload)
    end)
    CombatEvents.subscribe("OnKill", function(payload)
        local _ = payload
    end)
    CombatEvents.subscribe("OnDamageTaken", function(payload)
        local _ = payload
    end)
    return state
end

return ProcRuntime
