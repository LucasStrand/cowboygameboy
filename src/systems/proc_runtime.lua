local CombatEvents = require("src.systems.combat_events")
local DamagePacket = require("src.systems.damage_packet")
local DamageResolver = require("src.systems.damage_resolver")
local AttackProfiles = require("src.data.attack_profiles")
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

local function collectProcEntries(source_actor, payload)
    local entries = {}
    if source_actor and type(source_actor.getProcRules) == "function" then
        local actor_rules = source_actor:getProcRules()
        if actor_rules then
            for _, entry in ipairs(actor_rules) do
                entries[#entries + 1] = entry
            end
        end
    end
    if source_actor and source_actor.isEnemy and payload.packet and payload.packet.source then
        local pid = payload.packet.source.owner_source_id
        local prof = pid and AttackProfiles.get(pid) or nil
        if prof and prof.proc_rules then
            for _, rule in ipairs(prof.proc_rules) do
                entries[#entries + 1] = {
                    rule = rule,
                    meta = { kind = "attack_profile", profile_id = prof.id },
                }
            end
        end
    end
    return entries
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
    local meta = entry.meta or {}
    local owner_source_type = "perk"
    local owner_source_id = "proc"
    local md = {
        proc_rule_id = proc_rule_id,
        source_context_kind = "snapshot_only",
    }

    if meta.kind == "perk" and meta.perk then
        owner_source_type = "perk"
        owner_source_id = meta.perk.id
        md.proc_source_perk_id = meta.perk.id
        md.source_context_kind = "player_weapon_proc"
    elseif meta.kind == "attack_profile" then
        owner_source_type = "attack_profile"
        owner_source_id = meta.profile_id or "attack_profile"
    end

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
            owner_source_type = owner_source_type,
            owner_source_id = owner_source_id,
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
        metadata = md,
    })
end

local function queueEveryNthHit(entry, payload)
    local pre_defense = payload.pre_defense_damage or 0
    local effect = entry.rule.effect or {}
    local scaled_damage = math.max(
        effect.min_damage or 1,
        math.floor(pre_defense * (effect.damage_scale or 0))
    )
    local packet = buildProcPacket(entry, payload, scaled_damage)
    local source_actor = payload.source_actor
    DamageResolver.enqueueSecondaryJob({
        delay = effect.delay ~= nil and effect.delay or 0.08,
        packet = packet,
        source_actor = source_actor,
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
    local source_actor = payload.source_actor
    if not source_actor or not payload.source_ref or payload.source_ref.owner_actor_id ~= source_actor.actorId then
        return
    end

    for _, entry in ipairs(collectProcEntries(source_actor, payload)) do
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
                    queueEveryNthHit(entry, payload)
                end
            end
        end
    end
end

function ProcRuntime.init(_player)
    local state = {
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
