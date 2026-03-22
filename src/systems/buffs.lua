local CombatEvents = require("src.systems.combat_events")
local DamagePacket = require("src.systems.damage_packet")
local DamageResolver = require("src.systems.damage_resolver")
local SourceRef = require("src.systems.source_ref")
local Statuses = require("src.data.statuses")

local Buffs = {}
Buffs.__index = Buffs

local ICON_DIR_BUFF = "assets/[VerArc Stash] Basic_Skills_and_Buffs/Buffs/"
local ICON_DIR_DEBUFF = "assets/[VerArc Stash] Basic_Skills_and_Buffs/Debuffs/"

local HARD_CC_DR_WINDOW = 6.0
local HARD_CC_IMMUNITY = 4.0
local BOSS_CC_DURATION_SCALE = 0.20
local BOSS_CC_IMMUNITY = 3.0
local HARD_CC_STEP_SCALE = { 1.0, 0.5, 0.25 }

local iconCache = {}
local definitions = {}

Buffs._definitions = definitions
Buffs.aliases = Statuses.aliases

local function cloneValue(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for k, v in pairs(value) do
        copy[k] = cloneValue(v)
    end
    return copy
end

local function shallowArray(list)
    local out = {}
    for i, value in ipairs(list or {}) do
        out[i] = value
    end
    return out
end

local function normalizeId(id)
    return Buffs.aliases[id] or id
end

local function definitionDuration(def)
    if def.duration ~= nil then
        return def.duration
    end
    return def.base_duration
end

local function getIcon(filename, isBuff)
    if not filename then
        return false
    end
    if iconCache[filename] ~= nil then
        return iconCache[filename]
    end
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

local function sourceRefFrom(spec)
    if type(spec) == "table" and (spec.owner_actor_id or spec.owner_source_type or spec.owner_source_id) then
        return SourceRef.new(spec)
    end
    return SourceRef.new({})
end

local function trackerOwnerActor(tracker, runtime_ctx)
    if runtime_ctx and runtime_ctx.owner_actor then
        return runtime_ctx.owner_actor
    end
    return tracker.owner_actor
end

local function trackerOwnerKind(tracker, runtime_ctx)
    if runtime_ctx and runtime_ctx.target_kind then
        return runtime_ctx.target_kind
    end
    return tracker.owner_kind or "enemy"
end

local function ensureTrackerDefaults(tracker)
    tracker.instances = tracker.instances or tracker.active or {}
    tracker.active = tracker.instances
    tracker.tag_counts = tracker.tag_counts or {}
    tracker.aggregated_stat_mods = tracker.aggregated_stat_mods or {}
    tracker.cc_state = tracker.cc_state or {
        hard_cc_count = 0,
        hard_cc_window_timer = 0,
        hard_cc_immunity_timer = 0,
    }
    tracker.visual_state = tracker.visual_state or {}
    tracker._instance_counter = tracker._instance_counter or 0
    tracker._dirty = tracker._dirty ~= false
    return tracker
end

local function emitStatusEvent(name, payload)
    CombatEvents.emit(name, payload or {})
end

local function isNegative(def)
    if def.polarity then
        return def.polarity == "negative"
    end
    return def.isBuff == false
end

local function shouldRemoveByRules(def, rules, default_negative)
    rules = rules or {}
    if rules.negative ~= nil then
        return rules.negative and isNegative(def)
    end
    if rules.positive ~= nil then
        return rules.positive and not isNegative(def)
    end
    if rules.hard_cc and def.category == "hard_cc" then
        return true
    end
    if rules.soft_cc and def.category == "soft_cc" then
        return true
    end
    if rules.tags then
        local wanted = {}
        for _, tag in ipairs(rules.tags) do
            wanted[tag] = true
        end
        for _, tag in ipairs(def.tags or {}) do
            if wanted[tag] then
                return true
            end
        end
        return false
    end
    return default_negative and isNegative(def) or (not default_negative and not isNegative(def))
end

local function recalcAggregates(tracker)
    local tag_counts = {}
    local stat_mods = {}
    local visuals = {
        jitterAmp = 0,
        jitterFreq = 0,
        tint = nil,
    }
    local tintR, tintG, tintB, tintA = 0, 0, 0, 0
    local hasTint = false

    for _, instance in pairs(tracker.instances) do
        local def = instance.def
        local stack_count = instance.stacks or 1

        for _, tag in ipairs(def.tags or {}) do
            tag_counts[tag] = (tag_counts[tag] or 0) + 1
        end
        for _, tag in ipairs(def.granted_target_tags or {}) do
            tag_counts[tag] = (tag_counts[tag] or 0) + 1
        end

        for stat, value in pairs(def.statMods or def.stat_mods or {}) do
            stat_mods[stat] = (stat_mods[stat] or 0) + value * stack_count
        end

        local visual = def.visuals or def.visual
        if visual and visual.jitter then
            local amp = visual.jitter.amp or visual.jitter[1]
            local freq = visual.jitter.freq or visual.jitter[2] or 15
            if type(amp) == "number" and amp > 0 then
                visuals.jitterAmp = visuals.jitterAmp + amp * stack_count
                visuals.jitterFreq = math.max(visuals.jitterFreq, freq)
            end
        end
        if visual and visual.tint then
            tintR = tintR + visual.tint[1]
            tintG = tintG + visual.tint[2]
            tintB = tintB + visual.tint[3]
            tintA = tintA + (visual.tint[4] or 0.15)
            hasTint = true
        end
    end

    visuals.tint = hasTint and { tintR, tintG, tintB, tintA } or nil
    tracker.tag_counts = tag_counts
    tracker.aggregated_stat_mods = stat_mods
    tracker.visual_state = visuals
    tracker._dirty = false
end

local function ensureAggregates(tracker)
    ensureTrackerDefaults(tracker)
    if tracker._dirty then
        recalcAggregates(tracker)
    end
end

local function getInstanceKey(tracker, id)
    tracker._instance_counter = tracker._instance_counter + 1
    return string.format("%s#%d", tostring(id), tracker._instance_counter)
end

local function ccProfileScale(tracker)
    if tracker.cc_profile == "boss" then
        return BOSS_CC_DURATION_SCALE
    end
    return 1.0
end

local function applyHardCCDuration(tracker, base_duration)
    local cc_state = tracker.cc_state
    if cc_state.hard_cc_immunity_timer > 0 then
        return 0
    end
    local step = cc_state.hard_cc_count + 1
    local scale = HARD_CC_STEP_SCALE[step]
    if not scale then
        cc_state.hard_cc_immunity_timer = HARD_CC_IMMUNITY
        cc_state.hard_cc_window_timer = HARD_CC_DR_WINDOW
        return 0
    end
    cc_state.hard_cc_count = step
    cc_state.hard_cc_window_timer = HARD_CC_DR_WINDOW
    local duration = base_duration * scale * ccProfileScale(tracker)
    if tracker.cc_profile == "boss" and duration > 0 then
        cc_state.hard_cc_immunity_timer = math.max(cc_state.hard_cc_immunity_timer or 0, BOSS_CC_IMMUNITY)
    end
    return duration
end

local function buildRemovalPayload(tracker, instance, reason, opts)
    return {
        status_id = instance.id,
        category = instance.category,
        source = cloneValue(instance.source),
        owner_actor_id = tracker.owner_actor_id,
        target_id = tracker.owner_actor_id,
        reason = reason,
        remaining_duration = instance.remaining_duration,
        stacks = instance.stacks,
        metadata = cloneValue(instance.metadata),
        opts = opts,
    }
end

local function removeInstanceByKey(tracker, key, reason, opts)
    local instance = tracker.instances[key]
    if not instance then
        return false, nil
    end
    local owner_actor = tracker.owner_actor
    if instance.def.on_remove and owner_actor then
        instance.def.on_remove(owner_actor, instance, reason)
    end
    tracker.instances[key] = nil
    tracker._dirty = true

    local event_name = reason == "expire" and "status_expired" or "status_removed"
    emitStatusEvent(event_name, buildRemovalPayload(tracker, instance, reason, opts))
    return true, instance
end

local function buildTickPacket(instance, stack_count)
    local snapshot = cloneValue(instance.snapshot_data or {})
    local tick_damage = snapshot.tick_damage
    if type(tick_damage) ~= "number" then
        return nil
    end

    local per_stack = snapshot.tick_damage_per_stack ~= false
    local final_base = per_stack and (tick_damage * math.max(1, stack_count)) or tick_damage
    local source_context = cloneValue(snapshot.source_context or {})
    source_context.base_min = final_base
    source_context.base_max = final_base
    source_context.damage = source_context.damage or 1
    source_context.physical_damage = source_context.physical_damage or 0
    source_context.magical_damage = source_context.magical_damage or 0
    source_context.true_damage = source_context.true_damage or 0
    source_context.crit_chance = source_context.crit_chance or 0
    source_context.crit_damage = source_context.crit_damage or 1.5
    source_context.armor_pen = source_context.armor_pen or 0
    source_context.magic_pen = source_context.magic_pen or 0

    return DamagePacket.new({
        kind = "status_tick",
        family = snapshot.family or instance.family or "physical",
        base_min = final_base,
        base_max = final_base,
        can_crit = snapshot.can_crit == true,
        counts_as_hit = false,
        can_trigger_on_hit = false,
        can_trigger_proc = false,
        can_lifesteal = false,
        allow_zero_damage = snapshot.allow_zero_damage == true,
        source = instance.source,
        tags = shallowArray(snapshot.tags or instance.tags or {}),
        target_id = instance.target and instance.target.target_id or nil,
        snapshot_data = {
            source_context = source_context,
        },
        metadata = {
            source_context_kind = "snapshot_only",
            ignore_block = true,
            status_id = instance.id,
        },
    })
end

local function performTick(tracker, instance, runtime_ctx)
    local owner_actor = trackerOwnerActor(tracker, runtime_ctx)
    if instance.def.legacy_tick and owner_actor then
        instance.def.legacy_tick(owner_actor, instance.tick_interval or 0, instance.stacks or 1, instance)
    end

    local packet = buildTickPacket(instance, instance.stacks or 1)
    if not packet or not owner_actor then
        emitStatusEvent("status_ticked", {
            status_id = instance.id,
            owner_actor_id = tracker.owner_actor_id,
            target_id = tracker.owner_actor_id,
            final_applied_damage = 0,
            stacks = instance.stacks,
        })
        return nil
    end

    local result = DamageResolver.resolve_packet({
        packet = packet,
        source_actor = runtime_ctx and runtime_ctx.source_actor,
        target_actor = owner_actor,
        target_kind = trackerOwnerKind(tracker, runtime_ctx),
        world = runtime_ctx and runtime_ctx.world,
    })

    emitStatusEvent("status_ticked", {
        status_id = instance.id,
        category = instance.category,
        source = cloneValue(instance.source),
        owner_actor_id = tracker.owner_actor_id,
        target_id = tracker.owner_actor_id,
        final_applied_damage = result and result.final_damage or 0,
        stacks = instance.stacks,
        packet_kind = packet.kind,
        family = packet.family,
        target_killed = result and result.target_killed or false,
    })

    return result
end

local function triggerShockOverload(tracker, instance, spec)
    local owner_actor = trackerOwnerActor(tracker, spec.runtime_ctx)
    if not owner_actor then
        return
    end

    local overload_damage = instance.snapshot_data and instance.snapshot_data.overload_damage or 0
    overload_damage = math.max(1, math.floor(overload_damage))
    local source_context = cloneValue(instance.snapshot_data and instance.snapshot_data.source_context or {})
    source_context.base_min = overload_damage
    source_context.base_max = overload_damage
    source_context.damage = source_context.damage or 1
    source_context.physical_damage = source_context.physical_damage or 0
    source_context.magical_damage = source_context.magical_damage or 0
    source_context.true_damage = source_context.true_damage or 0
    source_context.crit_chance = 0
    source_context.crit_damage = 1.5
    source_context.armor_pen = source_context.armor_pen or 0
    source_context.magic_pen = source_context.magic_pen or 0

    local packet = DamagePacket.new({
        kind = "status_payoff_hit",
        family = "magical",
        base_min = overload_damage,
        base_max = overload_damage,
        can_crit = false,
        counts_as_hit = false,
        can_trigger_on_hit = false,
        can_trigger_proc = false,
        can_lifesteal = false,
        source = instance.source,
        tags = { "status:shock", "shock_overload" },
        target_id = tracker.owner_actor_id,
        snapshot_data = {
            source_context = source_context,
        },
        metadata = {
            source_context_kind = "snapshot_only",
            ignore_block = true,
            status_id = "shock",
        },
    })

    DamageResolver.resolve_packet({
        packet = packet,
        source_actor = spec.source_actor,
        target_actor = owner_actor,
        target_kind = trackerOwnerKind(tracker, spec.runtime_ctx),
        world = spec.runtime_ctx and spec.runtime_ctx.world,
    })

    Buffs.consume(tracker, "shock", "consume", spec.runtime_ctx)
    Buffs.applyStatus(tracker, {
        id = "stun",
        source = instance.source,
        duration = (instance.snapshot_data and instance.snapshot_data.overload_stun_duration) or 0.8,
        runtime_ctx = spec.runtime_ctx,
        target_actor = owner_actor,
        source_actor = spec.source_actor,
        metadata = {
            triggered_by = "shock_overload",
        },
    })
end

function Buffs.define(def)
    assert(def.id, "status definition needs an id")
    local canonical = cloneValue(def)
    canonical.maxStacks = canonical.maxStacks or canonical.max_stacks or 1
    canonical.max_stacks = canonical.max_stacks or canonical.maxStacks
    canonical.base_duration = canonical.base_duration or canonical.duration
    canonical.duration = canonical.duration or canonical.base_duration
    canonical.stack_mode = canonical.stack_mode or "none"
    canonical.duration_mode = canonical.duration_mode or "refresh"
    canonical.isBuff = canonical.isBuff ~= false
    canonical.tags = shallowArray(canonical.tags)
    canonical.granted_target_tags = shallowArray(canonical.granted_target_tags)
    definitions[canonical.id] = canonical
end

function Buffs.getDef(id)
    return definitions[normalizeId(id)]
end

for _, def in pairs(Statuses.definitions or {}) do
    Buffs.define(def)
end

function Buffs.newTracker(owner_ref, opts)
    opts = opts or {}
    local instances = {}
    local tracker = {
        owner_ref = cloneValue(owner_ref or {}),
        owner_actor = opts.owner_actor,
        owner_actor_id = opts.owner_actor_id or (owner_ref and owner_ref.owner_actor_id) or (opts.owner_actor and opts.owner_actor.actorId) or "unknown_target",
        owner_kind = opts.owner_kind or "enemy",
        instances = instances,
        active = instances,
        tag_counts = {},
        aggregated_stat_mods = {},
        cc_profile = opts.cc_profile or "normal",
        cc_state = {
            hard_cc_count = 0,
            hard_cc_window_timer = 0,
            hard_cc_immunity_timer = 0,
        },
        visual_state = {},
        _instance_counter = 0,
        _dirty = true,
    }
    return tracker
end

function Buffs.applyStatus(tracker, application_spec)
    tracker = ensureTrackerDefaults(tracker)
    application_spec = application_spec or {}

    local id = normalizeId(application_spec.id)
    local def = definitions[id]
    if not def then
        return false, "unknown_status"
    end

    local max_stacks = def.max_stacks or def.maxStacks or 1
    local requested_stacks = math.max(1, math.floor(application_spec.stacks or 1))
    local duration = application_spec.duration
    if duration == nil then
        duration = definitionDuration(def)
    end
    if duration == nil then
        duration = math.huge
    end

    if def.category == "hard_cc" or (def.cc_rules and def.cc_rules.dr_family == "hard_cc") then
        duration = applyHardCCDuration(tracker, duration)
        if duration <= 0 then
            return false, "immune"
        end
    end

    local key = id
    local existing = tracker.instances[key]
    if def.stack_mode == "independent" then
        key = getInstanceKey(tracker, id)
        existing = nil
    end

    local status_source = sourceRefFrom(application_spec.source)
    local metadata = cloneValue(application_spec.metadata or {})
    local event_name = "status_applied"
    local created = false

    if not existing then
        existing = {
            key = key,
            id = id,
            name = def.name or id,
            category = def.category or (def.isBuff and "buff" or "debuff"),
            def = def,
            tags = shallowArray(def.tags),
            source = status_source,
            target = {
                target_id = tracker.owner_actor_id,
            },
            stacks = math.min(max_stacks, requested_stacks),
            remaining_duration = duration,
            tick_interval = def.tick_interval,
            tick_timer = def.tick_interval or 0,
            snapshot_data = cloneValue(application_spec.snapshot_data or {}),
            visual_priority = def.visual_priority or 0,
            cleanse_rules = cloneValue(def.cleanse_rules or {}),
            cc_rules = cloneValue(def.cc_rules or {}),
            metadata = metadata,
            family = application_spec.family or metadata.family,
        }
        tracker.instances[key] = existing
        created = true
    else
        if def.stack_mode == "intensity" then
            local before = existing.stacks
            existing.stacks = math.min(max_stacks, existing.stacks + requested_stacks)
            event_name = existing.stacks ~= before and "status_stacked" or "status_refreshed"
        elseif def.stack_mode == "duration" then
            existing.stacks = math.max(existing.stacks, math.min(max_stacks, requested_stacks))
            event_name = "status_refreshed"
        elseif def.stack_mode == "none" then
            existing.stacks = math.max(existing.stacks, 1)
            event_name = "status_refreshed"
        end

        local duration_mode = def.duration_mode or "refresh"
        if duration_mode == "refresh" then
            existing.remaining_duration = duration
        elseif duration_mode == "extend" then
            existing.remaining_duration = math.max(0, existing.remaining_duration or 0) + duration
        elseif duration_mode == "keep_longer" then
            existing.remaining_duration = math.max(existing.remaining_duration or 0, duration)
        end
        existing.snapshot_data = cloneValue(application_spec.snapshot_data or existing.snapshot_data or {})
        existing.source = status_source
        existing.metadata = metadata
    end

    if created and def.on_apply and tracker.owner_actor then
        def.on_apply(tracker.owner_actor, existing.stacks, existing)
    end

    tracker._dirty = true
    emitStatusEvent(event_name, {
        status_id = id,
        category = existing.category,
        source = cloneValue(existing.source),
        owner_actor_id = tracker.owner_actor_id,
        target_id = tracker.owner_actor_id,
        stacks = existing.stacks,
        remaining_duration = existing.remaining_duration,
        visual_priority = existing.visual_priority,
        metadata = cloneValue(existing.metadata),
    })

    if id == "shock" and existing.stacks >= (def.max_stacks or 3) and not application_spec.skip_specials then
        triggerShockOverload(tracker, existing, application_spec)
    end

    return true, existing
end

function Buffs.removeStatus(tracker, status_id, reason, opts)
    tracker = ensureTrackerDefaults(tracker)
    local id = normalizeId(status_id)
    local removed = false
    for key, instance in pairs(tracker.instances) do
        if instance.id == id then
            local ok = removeInstanceByKey(tracker, key, reason or "manual", opts)
            removed = ok or removed
        end
    end
    return removed
end

function Buffs.cleanse(tracker, rules, opts)
    tracker = ensureTrackerDefaults(tracker)
    local removed = 0
    for key, instance in pairs(cloneValue(tracker.instances)) do
        if shouldRemoveByRules(instance.def, rules, true) then
            if removeInstanceByKey(tracker, key, "cleanse", opts) then
                removed = removed + 1
            end
        end
    end
    return removed
end

function Buffs.purge(tracker, rules, opts)
    tracker = ensureTrackerDefaults(tracker)
    local removed = 0
    for key, instance in pairs(cloneValue(tracker.instances)) do
        if shouldRemoveByRules(instance.def, rules, false) then
            if removeInstanceByKey(tracker, key, "purge", opts) then
                removed = removed + 1
            end
        end
    end
    return removed
end

function Buffs.consume(tracker, status_id, reason, opts)
    return Buffs.removeStatus(tracker, status_id, reason or "consume", opts)
end

function Buffs.update(tracker, dt, runtime_ctx)
    tracker = ensureTrackerDefaults(tracker)
    runtime_ctx = runtime_ctx or {}
    if runtime_ctx.owner_actor then
        tracker.owner_actor = runtime_ctx.owner_actor
        tracker.owner_actor_id = runtime_ctx.owner_actor.actorId or tracker.owner_actor_id
    end
    if runtime_ctx.target_kind then
        tracker.owner_kind = runtime_ctx.target_kind
    end

    local cc_state = tracker.cc_state
    if cc_state.hard_cc_window_timer > 0 then
        cc_state.hard_cc_window_timer = math.max(0, cc_state.hard_cc_window_timer - dt)
        if cc_state.hard_cc_window_timer <= 0 then
            cc_state.hard_cc_count = 0
        end
    end
    if cc_state.hard_cc_immunity_timer > 0 then
        cc_state.hard_cc_immunity_timer = math.max(0, cc_state.hard_cc_immunity_timer - dt)
    end

    local expired = {}
    for key, instance in pairs(tracker.instances) do
        local def = instance.def

        if def.tick_interval and def.tick_interval > 0 then
            instance.tick_timer = (instance.tick_timer or def.tick_interval) - dt
            while instance.tick_timer <= 0 and instance.remaining_duration > 0 do
                instance.tick_timer = instance.tick_timer + def.tick_interval
                performTick(tracker, instance, runtime_ctx)
            end
        elseif def.legacy_tick and tracker.owner_actor then
            def.legacy_tick(tracker.owner_actor, dt, instance.stacks or 1, instance)
        end

        if instance.remaining_duration ~= math.huge then
            instance.remaining_duration = instance.remaining_duration - dt
            if instance.remaining_duration <= 0 then
                expired[#expired + 1] = key
            end
        end
    end

    for _, key in ipairs(expired) do
        removeInstanceByKey(tracker, key, "expire", runtime_ctx)
    end

    ensureAggregates(tracker)
end

function Buffs.getStatMods(tracker)
    if not tracker then
        return {}
    end
    ensureAggregates(tracker)
    return cloneValue(tracker.aggregated_stat_mods)
end

function Buffs.hasStatus(tracker, id)
    if not tracker then
        return false
    end
    id = normalizeId(id)
    for _, instance in pairs(tracker.instances or {}) do
        if instance.id == id then
            return true
        end
    end
    return false
end

function Buffs.hasTag(tracker, tag)
    if not tracker then
        return false
    end
    ensureAggregates(tracker)
    return (tracker.tag_counts[tag] or 0) > 0
end

function Buffs.getTopStatuses(tracker, limit, opts)
    if not tracker then
        return {}
    end
    ensureAggregates(tracker)
    opts = opts or {}
    local out = {}
    for _, instance in pairs(tracker.instances or {}) do
        out[#out + 1] = {
            id = instance.id,
            name = instance.name,
            stacks = instance.stacks,
            remaining_duration = instance.remaining_duration,
            def = instance.def,
            category = instance.category,
            visual_priority = instance.visual_priority or 0,
            icon = instance.def.icon,
            isBuff = instance.def.isBuff ~= false,
            fallback_color = (instance.def.visuals or instance.def.visual or {}).fallback_color,
        }
    end
    table.sort(out, function(a, b)
        if a.visual_priority ~= b.visual_priority then
            return a.visual_priority > b.visual_priority
        end
        if a.isBuff ~= b.isBuff then
            return a.isBuff == false
        end
        return tostring(a.id) < tostring(b.id)
    end)
    if limit and #out > limit then
        while #out > limit do
            table.remove(out)
        end
    end
    return out
end

function Buffs.getControlState(tracker)
    return {
        stunned = Buffs.hasTag(tracker, "cc:stunned"),
    }
end

function Buffs.has(tracker, id)
    return Buffs.hasStatus(tracker, id)
end

function Buffs.stacks(tracker, id)
    if not tracker then
        return 0
    end
    id = normalizeId(id)
    local total = 0
    for _, instance in pairs(tracker.instances or {}) do
        if instance.id == id then
            total = total + (instance.stacks or 0)
        end
    end
    return total
end

function Buffs.apply(tracker, id, stacks)
    return Buffs.applyStatus(tracker, {
        id = id,
        stacks = stacks,
    })
end

function Buffs.remove(tracker, id, _owner)
    return Buffs.removeStatus(tracker, id, "manual")
end

function Buffs.clearAll(tracker, _owner)
    if not tracker then
        return
    end
    for key in pairs(cloneValue(tracker.instances or {})) do
        removeInstanceByKey(tracker, key, "manual", nil)
    end
end

function Buffs.getVisuals(tracker)
    if not tracker then
        return {
            jitterAmp = 0,
            jitterFreq = 0,
            tint = nil,
        }
    end
    ensureAggregates(tracker)
    return cloneValue(tracker.visual_state)
end

local function drawFallbackIcon(entry, x, y, scale, alpha)
    local icon_size = 16 * scale
    local color = entry.fallback_color or (entry.isBuff and { 0.3, 0.7, 0.34, 1 } or { 0.8, 0.24, 0.24, 1 })
    love.graphics.setColor(0.08, 0.08, 0.1, 0.86 * alpha)
    love.graphics.rectangle("fill", x, y, icon_size, icon_size, 3, 3)
    love.graphics.setColor(color[1], color[2], color[3], 0.95 * alpha)
    love.graphics.rectangle("fill", x + 1, y + 1, icon_size - 2, icon_size - 2, 2, 2)
    love.graphics.setColor(0, 0, 0, 0.6 * alpha)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, icon_size - 1, icon_size - 1, 2, 2)
    local label = string.upper(string.sub(entry.id or "?", 1, 1))
    love.graphics.setColor(0.08, 0.06, 0.05, 0.9 * alpha)
    love.graphics.print(label, x + icon_size * 0.32, y + icon_size * 0.15)
end

function Buffs.drawIcons(tracker, x, y, scale)
    if not tracker then
        return
    end
    scale = scale or 2
    local icon_size = 16 * scale
    local gap = 2
    local draw_x = x
    local entries = Buffs.getTopStatuses(tracker, 5)

    for _, entry in ipairs(entries) do
        local duration = entry.def and definitionDuration(entry.def) or nil
        local alpha = 1
        if entry.remaining_duration and entry.remaining_duration ~= math.huge and entry.remaining_duration < 3 then
            alpha = 0.5 + 0.5 * math.sin(love.timer.getTime() * 8)
        end

        local icon = getIcon(entry.icon, entry.isBuff)
        if icon then
            love.graphics.setColor(1, 1, 1, alpha)
            love.graphics.draw(icon, draw_x, y, 0, scale, scale)
        else
            drawFallbackIcon(entry, draw_x, y, scale, alpha)
        end

        if (entry.stacks or 0) > 1 then
            love.graphics.setColor(1, 1, 1, alpha)
            love.graphics.print(tostring(entry.stacks), draw_x + icon_size - 8, y + icon_size - 10)
        end
        if entry.remaining_duration and entry.remaining_duration ~= math.huge and duration then
            local frac = math.max(0, entry.remaining_duration / duration)
            local fill = entry.isBuff and { 0.2, 0.8, 0.2 } or { 0.8, 0.2, 0.2 }
            love.graphics.setColor(fill[1], fill[2], fill[3], 0.8 * alpha)
            love.graphics.rectangle("fill", draw_x, y + icon_size + 1, icon_size * frac, 2)
        end
        draw_x = draw_x + icon_size + gap
    end

    love.graphics.setColor(1, 1, 1)
end

return Buffs
