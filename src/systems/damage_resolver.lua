local CombatEvents = require("src.systems.combat_events")
local DamagePacket = require("src.systems.damage_packet")
local GameRng = require("src.systems.game_rng")
local SourceRef = require("src.systems.source_ref")
local StatRuntime = require("src.systems.stat_runtime")

local DamageResolver = {
    _secondary_jobs = {},
}

local CRIT_DAMAGE_DEFAULT = 1.5
local CRIT_OVERCAP_TO_CRIT_DAMAGE_RATE = 0

local function targetId(target)
    if not target then
        return "unknown_target"
    end
    return target.actorId or target.typeId or target.name or "unknown_target"
end

local function debugResolvedHit(result)
    if not DEBUG or not debugLog then
        return
    end

    debugLog(string.format(
        "[damage_resolver] kind=%s family=%s source=%s/%s target=%s rolled=%s crit=%s defense=%s final=%s",
        tostring(result.packet_kind),
        tostring(result.family),
        tostring(result.source_ref and result.source_ref.owner_source_type or "unknown"),
        tostring(result.source_ref and result.source_ref.owner_source_id or "unknown"),
        tostring(result.target_id),
        tostring(result.rolled_base_damage),
        tostring(result.was_crit),
        tostring(result.effective_defense),
        tostring(result.final_damage)
    ))
end

local function cloneTable(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for k, v in pairs(value) do
        copy[k] = cloneTable(v)
    end
    return copy
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function normalizeCritDamage(value)
    if type(value) == "number" and value > 0 then
        return value
    end
    return CRIT_DAMAGE_DEFAULT
end

local function computePlayerNormalizedStats(player, gun_def)
    local ctx = StatRuntime.build_player_context(player, gun_def, player.baseGunStats)
    return StatRuntime.compute_actor_stats(ctx)
end

local function neutralSourceContext(packet)
    return {
        base_min = packet.base_min or 0,
        base_max = packet.base_max or packet.base_min or 0,
        damage = 1,
        physical_damage = 0,
        magical_damage = 0,
        true_damage = 0,
        crit_chance = 0,
        crit_damage = CRIT_DAMAGE_DEFAULT,
        armor_pen = 0,
        magic_pen = 0,
    }
end

local function sourceContextFromSnapshot(packet)
    local context = packet.snapshot_data and packet.snapshot_data.source_context
    if not context then
        return neutralSourceContext(packet)
    end

    local copy = cloneTable(context)
    copy.base_min = copy.base_min or packet.base_min or 0
    copy.base_max = copy.base_max or packet.base_max or copy.base_min or 0
    copy.damage = copy.damage or 1
    copy.physical_damage = copy.physical_damage or 0
    copy.magical_damage = copy.magical_damage or 0
    copy.true_damage = copy.true_damage or 0
    copy.crit_chance = copy.crit_chance or 0
    copy.crit_damage = normalizeCritDamage(copy.crit_damage)
    copy.armor_pen = copy.armor_pen or 0
    copy.magic_pen = copy.magic_pen or 0
    return copy
end

local function livePlayerWeaponContext(packet, source_actor)
    local metadata = packet.metadata or {}
    if not source_actor or not source_actor.getWeaponRuntime or not metadata.source_slot_index then
        return nil
    end
    if packet.source and source_actor.actorId ~= packet.source.owner_actor_id then
        return nil
    end

    local slot = source_actor:getWeaponRuntime(metadata.source_slot_index)
    if not slot or slot.mode ~= "weapon" or not slot.weapon_def then
        return nil
    end
    if metadata.source_weapon_id and slot.weapon_id ~= metadata.source_weapon_id then
        return nil
    end

    local stats = computePlayerNormalizedStats(source_actor, slot.weapon_def)
    local scale = metadata.base_scale or 1
    local base = (stats.projectile_damage or packet.base_min or 0) * scale
    return {
        base_min = base,
        base_max = base,
        damage = stats.damage or 1,
        physical_damage = stats.physical_damage or 0,
        magical_damage = stats.magical_damage or 0,
        true_damage = stats.true_damage or 0,
        crit_chance = stats.crit_chance or 0,
        crit_damage = normalizeCritDamage(stats.crit_damage),
        armor_pen = stats.armor_pen or 0,
        magic_pen = stats.magic_pen or 0,
    }
end

local function livePlayerMeleeContext(packet, source_actor)
    if not source_actor or not source_actor.getEffectiveStats then
        return nil
    end
    if packet.source and source_actor.actorId ~= packet.source.owner_actor_id then
        return nil
    end

    local stats = computePlayerNormalizedStats(source_actor, nil)
    local base = stats.melee_damage or packet.base_min or 0
    return {
        base_min = base,
        base_max = base,
        damage = stats.damage or 1,
        physical_damage = stats.physical_damage or 0,
        magical_damage = stats.magical_damage or 0,
        true_damage = stats.true_damage or 0,
        crit_chance = stats.crit_chance or 0,
        crit_damage = normalizeCritDamage(stats.crit_damage),
        armor_pen = stats.armor_pen or 0,
        magic_pen = stats.magic_pen or 0,
    }
end

local function liveEnemyContext(packet, source_actor)
    if not source_actor then
        return nil
    end
    if packet.source and source_actor.actorId ~= packet.source.owner_actor_id then
        return nil
    end

    local metadata = packet.metadata or {}
    if metadata.source_attack_id and packet.source and metadata.source_attack_id ~= packet.source.owner_source_id then
        return nil
    end

    local base = source_actor.damage or packet.base_min or 0
    return {
        base_min = base,
        base_max = base,
        damage = 1,
        physical_damage = 0,
        magical_damage = 0,
        true_damage = 0,
        crit_chance = 0,
        crit_damage = CRIT_DAMAGE_DEFAULT,
        armor_pen = 0,
        magic_pen = 0,
    }
end

local function resolveSourceContext(packet, source_actor)
    local context_kind = packet.metadata and packet.metadata.source_context_kind
    if context_kind == "player_weapon_projectile" then
        return livePlayerWeaponContext(packet, source_actor) or sourceContextFromSnapshot(packet)
    end
    if context_kind == "player_melee" then
        return livePlayerMeleeContext(packet, source_actor) or sourceContextFromSnapshot(packet)
    end
    if context_kind == "enemy_projectile" or context_kind == "enemy_contact" then
        return liveEnemyContext(packet, source_actor) or sourceContextFromSnapshot(packet)
    end
    return sourceContextFromSnapshot(packet)
end

local function getTargetDefenseState(target_actor, target_kind, packet)
    if target_kind == "player" then
        local stats = target_actor:getEffectiveStats()
        local allow_block = not (packet and packet.metadata and packet.metadata.ignore_block)
        return {
            armor = stats.armor or 0,
            magic_resist = stats.magicResist or 0,
            armor_shred = target_actor.armorShred or 0,
            magic_shred = target_actor.magicShred or 0,
            incoming_damage_mul = target_actor.incomingDamageMul or 1,
            incoming_physical_mul = target_actor.incomingPhysicalMul or 1,
            incoming_magical_mul = target_actor.incomingMagicalMul or 1,
            block_damage_mul = (allow_block and target_actor.blocking and (stats.blockReduction or 0) > 0)
                and (1 - stats.blockReduction)
                or 1,
        }
    end

    return {
        armor = target_actor.armor or 0,
        magic_resist = target_actor.magic_resist or 0,
        armor_shred = target_actor.armor_shred or 0,
        magic_shred = target_actor.magic_shred or 0,
        incoming_damage_mul = target_actor.incoming_damage_mul or 1,
        incoming_physical_mul = target_actor.incoming_physical_mul or 1,
        incoming_magical_mul = target_actor.incoming_magical_mul or 1,
        block_damage_mul = 1,
    }
end

local function rollBaseDamage(packet, source_context, target_id_value)
    local minv = source_context.base_min or packet.base_min or 0
    local maxv = source_context.base_max or packet.base_max or minv
    if maxv < minv then
        minv, maxv = maxv, minv
    end
    if maxv == minv then
        return minv
    end

    local channel = string.format(
        "damage_resolver.base.%s.%s.%s.%s",
        tostring(packet.kind),
        tostring(packet.source and packet.source.owner_source_id or "unknown"),
        tostring(target_id_value),
        tostring(packet.family)
    )
    return GameRng.randomFloat(channel, minv, maxv)
end

local function createSecondaryJobs(packet, result, target_actor)
    local metadata = packet.metadata or {}
    if not metadata.explosion_radius or packet.kind ~= "direct_hit" or not target_actor then
        return {}
    end

    local splash_base = math.max(1, math.floor((result.pre_defense_damage or 0) * (metadata.explosion_damage_scale or 0.5)))
    local source_ref = packet.source or SourceRef.new({})
    local secondary_source = SourceRef.new({
        owner_actor_id = source_ref.owner_actor_id,
        owner_source_type = source_ref.owner_source_type,
        owner_source_id = source_ref.owner_source_id,
        parent_source_id = source_ref.parent_source_id or source_ref.owner_source_id,
    })
    local secondary_packet = DamagePacket.new({
        kind = "delayed_secondary_hit",
        family = packet.family,
        base_min = splash_base,
        base_max = splash_base,
        can_crit = false,
        counts_as_hit = false,
        can_trigger_on_hit = false,
        can_trigger_proc = false,
        can_lifesteal = false,
        source = secondary_source,
        tags = { "explosion", "secondary" },
        snapshot_data = {
            source_context = {
                base_min = splash_base,
                base_max = splash_base,
                damage = 1,
                physical_damage = 0,
                magical_damage = 0,
                true_damage = 0,
                crit_chance = 0,
                crit_damage = CRIT_DAMAGE_DEFAULT,
                armor_pen = 0,
                magic_pen = 0,
            },
        },
    })

    return {
        {
            delay = metadata.explosion_delay or 0,
            packet = secondary_packet,
            source_actor = nil,
            target_selector = "enemies_in_radius",
            origin_x = target_actor.x + target_actor.w * 0.5,
            origin_y = target_actor.y + target_actor.h * 0.5,
            radius = metadata.explosion_radius,
            exclude_target_id = targetId(target_actor),
        }
    }
end

function DamageResolver.resolve_packet(spec)
    spec = spec or {}
    local packet = DamagePacket.new(spec.packet or {})
    local source_actor = spec.source_actor
    local target_actor = spec.target_actor
    local target_kind = spec.target_kind or ((target_actor and target_actor.isEnemy) and "enemy" or "player")
    local target_id_value = packet.target_id or targetId(target_actor)
    local source_context = resolveSourceContext(packet, source_actor)
    local result = {
        rolled_base_damage = 0,
        pre_defense_damage = 0,
        effective_defense = 0,
        final_damage = 0,
        was_crit = false,
        family = packet.family,
        packet_kind = packet.kind,
        source_ref = packet.source,
        target_id = target_id_value,
        target_killed = false,
        applied_minimum_damage = false,
        secondary_jobs = {},
        counts_as_hit = packet.counts_as_hit,
        tags = packet.tags,
        applied = false,
    }

    local rolled_base_damage = rollBaseDamage(packet, source_context, target_id_value)
    local damage_after_flat = rolled_base_damage

    local summed_add_pct = (source_context.damage or 1) - 1
    if packet.family == "physical" then
        summed_add_pct = summed_add_pct + (source_context.physical_damage or 0)
    elseif packet.family == "magical" then
        summed_add_pct = summed_add_pct + (source_context.magical_damage or 0)
    elseif packet.family == "true" then
        summed_add_pct = summed_add_pct + (source_context.true_damage or 0)
    end

    local damage_after_add_pct = damage_after_flat * (1 + summed_add_pct)
    local damage_after_mul = damage_after_add_pct

    local effective_crit_chance = packet.can_crit and (source_context.crit_chance or 0) or 0
    local crit_roll_chance = clamp(effective_crit_chance, 0, 1)
    local crit_overcap = math.max(0, effective_crit_chance - 1)
    local crit_damage = normalizeCritDamage(source_context.crit_damage) + crit_overcap * CRIT_OVERCAP_TO_CRIT_DAMAGE_RATE
    local damage_after_crit = damage_after_mul
    if packet.can_crit and crit_roll_chance > 0 then
        local crit_channel = string.format(
            "damage_resolver.crit.%s.%s.%s.%s",
            tostring(packet.kind),
            tostring(packet.source and packet.source.owner_source_id or "unknown"),
            tostring(target_id_value),
            tostring(packet.family)
        )
        if GameRng.randomChance(crit_channel, crit_roll_chance) then
            damage_after_crit = damage_after_mul * crit_damage
            result.was_crit = true
        end
    end

    local pre_defense_damage = damage_after_crit
    local defense_state = getTargetDefenseState(target_actor, target_kind, packet)
    local damage_after_mitigation = pre_defense_damage
    local effective_defense = 0

    if packet.family == "physical" or packet.family == "magical" then
        local defense_value
        local shred
        local pen
        if packet.family == "physical" then
            defense_value = defense_state.armor or 0
            shred = defense_state.armor_shred or 0
            pen = source_context.armor_pen or 0
        else
            defense_value = defense_state.magic_resist or 0
            shred = defense_state.magic_shred or 0
            pen = source_context.magic_pen or 0
        end
        effective_defense = math.max(0, defense_value - shred - pen)
        damage_after_mitigation = pre_defense_damage * (100 / (100 + effective_defense))
    end

    local damage_after_incoming_mods = damage_after_mitigation * (defense_state.incoming_damage_mul or 1)
    if packet.family == "physical" then
        damage_after_incoming_mods = damage_after_incoming_mods * (defense_state.incoming_physical_mul or 1)
    elseif packet.family == "magical" then
        damage_after_incoming_mods = damage_after_incoming_mods * (defense_state.incoming_magical_mul or 1)
    end
    damage_after_incoming_mods = damage_after_incoming_mods * (defense_state.block_damage_mul or 1)

    local final_damage = math.floor(damage_after_incoming_mods)
    if damage_after_incoming_mods > 0 and final_damage < 1 and not packet.allow_zero_damage then
        final_damage = 1
        result.applied_minimum_damage = true
    elseif final_damage < 0 then
        final_damage = 0
    end

    result.rolled_base_damage = rolled_base_damage
    result.pre_defense_damage = pre_defense_damage
    result.effective_defense = effective_defense
    result.final_damage = final_damage

    if final_damage <= 0 then
        debugResolvedHit(result)
        return result
    end

    local applied, applied_damage, killed = false, 0, false
    if target_actor and target_actor.applyResolvedDamage then
        applied, applied_damage, killed = target_actor:applyResolvedDamage(result, spec.world, packet)
    end

    if not applied then
        result.final_damage = applied_damage or 0
        debugResolvedHit(result)
        return result
    end

    result.applied = true
    result.final_damage = applied_damage or final_damage
    result.target_killed = killed == true
    result.secondary_jobs = createSecondaryJobs(packet, result, target_actor)

    for _, job in ipairs(result.secondary_jobs) do
        DamageResolver.enqueueSecondaryJob(job)
    end

    CombatEvents.emit("OnDamageTaken", {
        source_ref = result.source_ref,
        target_id = result.target_id,
        packet_kind = result.packet_kind,
        family = result.family,
        tags = packet.tags,
        rolled_base_damage = result.rolled_base_damage,
        pre_defense_damage = result.pre_defense_damage,
        effective_defense = result.effective_defense,
        final_applied_damage = result.final_damage,
        was_crit = result.was_crit,
        target_killed = result.target_killed,
        applied_minimum_damage = result.applied_minimum_damage,
    })

    if packet.counts_as_hit then
        CombatEvents.emit("OnHit", {
            source_ref = result.source_ref,
            target_id = result.target_id,
            packet_kind = result.packet_kind,
            family = result.family,
            tags = packet.tags,
            rolled_base_damage = result.rolled_base_damage,
            pre_defense_damage = result.pre_defense_damage,
            effective_defense = result.effective_defense,
            final_applied_damage = result.final_damage,
            was_crit = result.was_crit,
            target_killed = result.target_killed,
            applied_minimum_damage = result.applied_minimum_damage,
        })
    end

    if result.target_killed then
        CombatEvents.emit("OnKill", {
            source_ref = result.source_ref,
            target_id = result.target_id,
            packet_kind = result.packet_kind,
            family = result.family,
            tags = packet.tags,
            rolled_base_damage = result.rolled_base_damage,
            pre_defense_damage = result.pre_defense_damage,
            effective_defense = result.effective_defense,
            final_applied_damage = result.final_damage,
            was_crit = result.was_crit,
            target_killed = true,
            applied_minimum_damage = result.applied_minimum_damage,
        })
    end

    debugResolvedHit(result)
    return result
end

function DamageResolver.enqueueSecondaryJob(job)
    if job then
        table.insert(DamageResolver._secondary_jobs, job)
    end
end

function DamageResolver.processSecondaryJobs(ctx)
    ctx = ctx or {}
    local dt = ctx.dt or 0
    local remaining = {}
    local executed = {}

    for _, job in ipairs(DamageResolver._secondary_jobs) do
        local next_delay = math.max(0, (job.delay or 0) - dt)
        job.delay = next_delay

        if next_delay > 0 then
            table.insert(remaining, job)
        elseif job.target_selector == "enemies_in_radius" then
            for _, enemy in ipairs(ctx.enemies or {}) do
                if enemy.alive and targetId(enemy) ~= job.exclude_target_id then
                    local ex = enemy.x + enemy.w * 0.5
                    local ey = enemy.y + enemy.h * 0.5
                    local dx = ex - job.origin_x
                    local dy = ey - job.origin_y
                    if dx * dx + dy * dy <= (job.radius * job.radius) then
                        local result = DamageResolver.resolve_packet({
                            packet = job.packet,
                            source_actor = job.source_actor,
                            target_actor = enemy,
                            target_kind = "enemy",
                            world = ctx.world,
                        })
                        if result.applied then
                            table.insert(executed, {
                                result = result,
                                target_actor = enemy,
                                x = ex,
                                y = ey,
                            })
                        end
                    end
                end
            end
        end
    end

    DamageResolver._secondary_jobs = remaining
    return executed
end

function DamageResolver.resolve_direct_hit(spec)
    return DamageResolver.resolve_packet(spec)
end

return DamageResolver
