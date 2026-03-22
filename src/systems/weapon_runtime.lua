local CombatEvents = require("src.systems.combat_events")
local DamagePacket = require("src.systems.damage_packet")
local GameRng = require("src.systems.game_rng")
local Sfx = require("src.systems.sfx")
local SourceRef = require("src.systems.source_ref")
local StatRuntime = require("src.systems.stat_runtime")

local WeaponRuntime = {}

local function cloneTable(src)
    local out = {}
    for k, v in pairs(src or {}) do
        if type(v) == "table" then
            out[k] = cloneTable(v)
        else
            out[k] = v
        end
    end
    return out
end

local function shallowArray(src)
    local out = {}
    for i, v in ipairs(src or {}) do
        out[i] = v
    end
    return out
end

local function defaultAttackProfileId(gun_def)
    local base_stats = gun_def and gun_def.baseStats or {}
    if (base_stats.bulletCount or 1) > 1 or (base_stats.spreadAngle or 0) > 0 then
        return "projectile_spread"
    end
    return "projectile_basic"
end

local function adaptWeaponDef(gun_def)
    if not gun_def then
        return nil
    end

    local canonical = cloneTable(gun_def)
    canonical.attack_profile_id = canonical.attack_profile_id or defaultAttackProfileId(canonical)
    canonical.capabilities = canonical.capabilities or {}
    canonical.rules = canonical.rules or {}
    canonical.tags = shallowArray(canonical.tags)
    if #canonical.tags == 0 then
        canonical.tags = {
            "attack:projectile",
            "weapon:" .. tostring(canonical.id or "unknown"),
        }
    end
    return canonical
end

local function buildWeaponSourceRef(player, slot_runtime, parent_source_id)
    return SourceRef.new({
        owner_actor_id = player.actorId or "player",
        owner_source_type = "weapon_slot",
        owner_source_id = slot_runtime.weapon_id or ("slot_" .. tostring(slot_runtime.slot_index or 1)),
        parent_source_id = parent_source_id,
    })
end

local function debugDump(player, reason)
    if not DEBUG or not debugLog then
        return
    end

    local runtime = player.weaponRuntime
    if not runtime then
        return
    end

    debugLog(string.format("[weapon_runtime] %s active=%s", reason or "state", tostring(runtime.active_weapon_slot)))
    for _, slot in ipairs(runtime.weapon_slots or {}) do
        debugLog(string.format(
            "[weapon_runtime] slot=%d mode=%s weapon=%s ammo=%s reload=%.3f cooldown=%.3f shots_since_reload=%d profile=%s",
            slot.slot_index,
            tostring(slot.mode),
            tostring(slot.weapon_id or "none"),
            tostring(slot.ammo or 0),
            tonumber(slot.reload_timer or 0),
            tonumber(slot.cooldown_timer or 0),
            tonumber(slot.shots_since_reload or 0),
            tostring(slot.attack_profile_id or "none")
        ))
    end
end

local function legacyViewForSlot(slot)
    return {
        gun = slot.mode == "weapon" and slot.weapon_def or nil,
        ammo = slot.mode == "weapon" and slot.ammo or 0,
        reloading = slot.mode == "weapon" and (slot.reload_timer or 0) > 0 or false,
        reloadTimer = slot.mode == "weapon" and (slot.reload_timer or 0) or 0,
        shootCooldown = slot.mode == "weapon" and (slot.cooldown_timer or 0) or 0,
        mode = slot.mode,
        attack_profile_id = slot.attack_profile_id,
        shots_since_reload = slot.shots_since_reload or 0,
    }
end

local function currentSlot(player)
    local runtime = player.weaponRuntime
    if not runtime then
        return nil
    end
    return runtime.weapon_slots[runtime.active_weapon_slot]
end

local function computeResolvedStats(player, gun_def)
    if not gun_def then
        return nil
    end

    local ctx = StatRuntime.build_player_context(player, gun_def, player.baseGunStats)
    local normalized = StatRuntime.compute_actor_stats(ctx)
    return StatRuntime.export_legacy_stats(normalized)
end

local function computeNormalizedStats(player, gun_def)
    if not gun_def then
        return nil
    end

    local ctx = StatRuntime.build_player_context(player, gun_def, player.baseGunStats)
    return StatRuntime.compute_actor_stats(ctx)
end

local function snapshotSourceContext(base_damage, normalized)
    return {
        base_min = base_damage,
        base_max = base_damage,
        damage = normalized.damage or 1,
        physical_damage = normalized.physical_damage or 0,
        magical_damage = normalized.magical_damage or 0,
        true_damage = normalized.true_damage or 0,
        crit_chance = normalized.crit_chance or 0,
        crit_damage = normalized.crit_damage or 1.5,
        armor_pen = normalized.armor_pen or 0,
        magic_pen = normalized.magic_pen or 0,
    }
end

local function buildStatusApplications(ctx)
    local applications = {}
    for _, app in ipairs(ctx.gun.status_applications or {}) do
        applications[#applications + 1] = cloneTable(app)
    end
    return applications
end

local function buildProjectilePacket(ctx)
    local base_scale = ctx.base_scale or 1
    local base_damage = math.max(0, (ctx.normalized_stats.projectile_damage or 0) * base_scale)
    local family = ctx.gun.damageFamily or "physical"
    return DamagePacket.new({
        kind = "direct_hit",
        family = family,
        base_min = base_damage,
        base_max = base_damage,
        can_crit = true,
        counts_as_hit = true,
        can_trigger_on_hit = true,
        can_trigger_proc = true,
        can_lifesteal = true,
        source = ctx.source_ref,
        tags = { "projectile", ctx.gun.id or "gun" },
        status_applications = buildStatusApplications(ctx),
        snapshot_data = {
            source_context = snapshotSourceContext(base_damage, ctx.normalized_stats),
        },
        metadata = {
            source_context_kind = "player_weapon_projectile",
            source_slot_index = ctx.slot.slot_index,
            source_weapon_id = ctx.gun.id,
            source_attack_profile_id = ctx.slot.attack_profile_id,
            base_scale = base_scale,
            explosion_radius = ctx.stats.explosiveRounds and 60 or nil,
            explosion_damage_scale = ctx.stats.explosiveRounds and 0.5 or nil,
        },
    })
end

local ATTACK_PROFILES = {
    projectile_basic = function(ctx)
        local bullets = {}
        table.insert(bullets, {
            x = ctx.origin_x,
            y = ctx.origin_y,
            angle = ctx.angle,
            speed = ctx.stats.bulletSpeed,
            damage = math.floor((ctx.normalized_stats.projectile_damage or 0) * (ctx.base_scale or 1)),
            ricochet = ctx.stats.ricochetCount,
            explosive = ctx.stats.explosiveRounds,
            packet = buildProjectilePacket(ctx),
            source_actor = ctx.player,
            source_ref = ctx.source_ref,
            packet_kind = "direct_hit",
            damage_family = ctx.gun.damageFamily or "physical",
            damage_tags = { "projectile", ctx.gun.id or "gun" },
        })
        return bullets
    end,
    projectile_spread = function(ctx)
        local bullets = {}
        local count = ctx.stats.bulletCount or 1
        for i = 1, count do
            local bullet_angle = ctx.angle
            if count > 1 then
                local spread = ctx.stats.spreadAngle or 0
                bullet_angle = ctx.angle - spread / 2 + spread * ((i - 1) / (count - 1))
            end
            table.insert(bullets, {
                x = ctx.origin_x,
                y = ctx.origin_y,
                angle = bullet_angle,
                speed = ctx.stats.bulletSpeed,
                damage = math.floor((ctx.normalized_stats.projectile_damage or 0) * (ctx.base_scale or 1)),
                ricochet = ctx.stats.ricochetCount,
                explosive = ctx.stats.explosiveRounds,
                packet = buildProjectilePacket(ctx),
                source_actor = ctx.player,
                source_ref = ctx.source_ref,
                packet_kind = "direct_hit",
                damage_family = ctx.gun.damageFamily or "physical",
                damage_tags = { "projectile", ctx.gun.id or "gun" },
            })
        end
        return bullets
    end,
}

function WeaponRuntime.initPlayerLoadout(player, primary_gun, secondary_gun)
    local primary = adaptWeaponDef(primary_gun)
    local secondary = adaptWeaponDef(secondary_gun)

    player.weaponRuntime = {
        weapon_slots = {
            [1] = {
                slot_index = 1,
                mode = primary and "weapon" or "melee",
                weapon_id = primary and primary.id or nil,
                weapon_def = primary,
                attack_profile_id = primary and primary.attack_profile_id or nil,
                ammo = primary and (primary.baseStats.cylinderSize or 0) or 0,
                reload_timer = 0,
                cooldown_timer = 0,
                charges = nil,
                shots_since_reload = 0,
                passive_counters = {},
                per_target_counters = {},
                temporary_flags = {},
            },
            [2] = {
                slot_index = 2,
                mode = secondary and "weapon" or "melee",
                weapon_id = secondary and secondary.id or nil,
                weapon_def = secondary,
                attack_profile_id = secondary and secondary.attack_profile_id or nil,
                ammo = secondary and (secondary.baseStats.cylinderSize or 0) or 0,
                reload_timer = 0,
                cooldown_timer = 0,
                charges = nil,
                shots_since_reload = 0,
                passive_counters = {},
                per_target_counters = {},
                temporary_flags = {},
            },
        },
        active_slots = { 1, 2 },
        active_weapon_slot = 1,
    }

    WeaponRuntime.syncLegacyViews(player)
    debugDump(player, "init")
end

function WeaponRuntime.syncLegacyViews(player)
    local runtime = player.weaponRuntime
    if not runtime then
        return
    end

    -- Compatibility mirrors remain for UI/presentation and small glue seams only.
    -- Gameplay code must read authoritative slot state from weapon_runtime.
    player.weapons = {
        [1] = legacyViewForSlot(runtime.weapon_slots[1]),
        [2] = legacyViewForSlot(runtime.weapon_slots[2]),
    }
    player.activeWeaponSlot = runtime.active_weapon_slot

    local slot = currentSlot(player)
    if slot and slot.mode == "weapon" then
        player.ammo = slot.ammo or 0
        player.reloading = (slot.reload_timer or 0) > 0
        player.reloadTimer = slot.reload_timer or 0
        player.shootCooldown = slot.cooldown_timer or 0
    else
        player.ammo = 0
        player.reloading = false
        player.reloadTimer = 0
        player.shootCooldown = 0
    end
end

function WeaponRuntime.getSlot(player, slot_index)
    local runtime = player.weaponRuntime
    return runtime and runtime.weapon_slots[slot_index] or nil
end

function WeaponRuntime.getActiveSlot(player)
    return currentSlot(player)
end

function WeaponRuntime.getResolvedStats(player, slot_index)
    local slot = WeaponRuntime.getSlot(player, slot_index)
    if not slot or slot.mode ~= "weapon" or not slot.weapon_def then
        return nil
    end

    return computeResolvedStats(player, slot.weapon_def)
end

function WeaponRuntime.getResolvedStatsForGun(player, gun_def)
    return computeResolvedStats(player, gun_def)
end

function WeaponRuntime.isSlotReloading(player, slot_index)
    local slot = WeaponRuntime.getSlot(player, slot_index)
    return slot and slot.mode == "weapon" and (slot.reload_timer or 0) > 0 or false
end

function WeaponRuntime.getAmmoCapacity(player, slot_index)
    local stats = WeaponRuntime.getResolvedStats(player, slot_index)
    if not stats then
        return 0
    end
    return stats.cylinderSize or 0
end

function WeaponRuntime.setActiveSlot(player, slot_index)
    local runtime = player.weaponRuntime
    if not runtime or not runtime.weapon_slots[slot_index] then
        return false
    end
    runtime.active_weapon_slot = slot_index
    WeaponRuntime.syncLegacyViews(player)
    debugDump(player, "switch")
    return true
end

function WeaponRuntime.switchActiveSlot(player)
    local runtime = player.weaponRuntime
    if not runtime then
        return false
    end
    local new_slot = runtime.active_weapon_slot == 1 and 2 or 1
    return WeaponRuntime.setActiveSlot(player, new_slot)
end

function WeaponRuntime.equipWeapon(player, gun_def, slot_index)
    slot_index = slot_index or 2
    local slot = WeaponRuntime.getSlot(player, slot_index)
    if not slot then
        return false
    end

    local canonical = adaptWeaponDef(gun_def)
    slot.mode = canonical and "weapon" or "melee"
    slot.weapon_id = canonical and canonical.id or nil
    slot.weapon_def = canonical
    slot.attack_profile_id = canonical and canonical.attack_profile_id or nil
    slot.ammo = canonical and (canonical.baseStats.cylinderSize or 0) or 0
    slot.reload_timer = 0
    slot.cooldown_timer = 0
    slot.charges = nil
    slot.shots_since_reload = 0
    slot.passive_counters = {}
    slot.per_target_counters = {}
    slot.temporary_flags = {}

    player.weaponRuntime.active_weapon_slot = slot_index
    WeaponRuntime.syncLegacyViews(player)
    debugDump(player, "equip")
    return true
end

function WeaponRuntime.startReload(player, slot_index)
    local slot = WeaponRuntime.getSlot(player, slot_index)
    if not slot or slot.mode ~= "weapon" or not slot.weapon_def then
        return false
    end
    if (slot.reload_timer or 0) > 0 then
        return false
    end

    local resolved = WeaponRuntime.getResolvedStats(player, slot_index)
    local capacity = resolved and resolved.cylinderSize or 0
    if (slot.ammo or 0) >= capacity then
        return false
    end

    slot.reload_timer = resolved and resolved.reloadSpeed or 0
    CombatEvents.emit("OnReloadStarted", {
        source_ref = buildWeaponSourceRef(player, slot),
        slot_index = slot_index,
        slot_mode = slot.mode,
        weapon_id = slot.weapon_id,
        attack_profile_id = slot.attack_profile_id,
        owner_actor_id = player.actorId,
    })
    WeaponRuntime.syncLegacyViews(player)
    debugDump(player, "reload_started")
    return true
end

function WeaponRuntime.finishReload(player, slot_index)
    local slot = WeaponRuntime.getSlot(player, slot_index)
    if not slot or slot.mode ~= "weapon" or not slot.weapon_def then
        return false
    end

    local resolved = WeaponRuntime.getResolvedStats(player, slot_index)
    slot.reload_timer = 0
    slot.ammo = resolved and resolved.cylinderSize or 0
    slot.shots_since_reload = 0
    Sfx.play("reload")

    CombatEvents.emit("OnReloadFinished", {
        source_ref = buildWeaponSourceRef(player, slot),
        slot_index = slot_index,
        slot_mode = slot.mode,
        weapon_id = slot.weapon_id,
        attack_profile_id = slot.attack_profile_id,
        owner_actor_id = player.actorId,
    })
    WeaponRuntime.syncLegacyViews(player)
    debugDump(player, "reload_finished")
    return true
end

function WeaponRuntime.addAmmo(player, slot_index, amount, reason)
    amount = amount or 0
    if amount == 0 then
        return 0
    end

    local slot = WeaponRuntime.getSlot(player, slot_index)
    if not slot or slot.mode ~= "weapon" then
        if DEBUG and debugLog then
            debugLog(string.format("[weapon_runtime] ignored ammo delta=%s on slot=%s reason=%s", tostring(amount), tostring(slot_index), tostring(reason)))
        end
        return 0
    end

    local capacity = WeaponRuntime.getAmmoCapacity(player, slot_index)
    local before = slot.ammo or 0
    slot.ammo = math.max(0, math.min(capacity, before + amount))
    WeaponRuntime.syncLegacyViews(player)
    debugDump(player, "ammo_delta")
    return slot.ammo - before
end

function WeaponRuntime.tick(player, dt)
    local runtime = player.weaponRuntime
    if not runtime then
        return
    end

    local finished_reload_active = false

    for _, slot in ipairs(runtime.weapon_slots) do
        if slot.mode == "weapon" then
            if (slot.cooldown_timer or 0) > 0 then
                slot.cooldown_timer = math.max(0, slot.cooldown_timer - dt)
            end
            if (slot.reload_timer or 0) > 0 then
                slot.reload_timer = slot.reload_timer - dt
                if slot.reload_timer <= 0 then
                    slot.reload_timer = 0
                    WeaponRuntime.finishReload(player, slot.slot_index)
                    if slot.slot_index == runtime.active_weapon_slot then
                        finished_reload_active = true
                    end
                end
            end
        end
    end

    WeaponRuntime.syncLegacyViews(player)
    if finished_reload_active and player.stats.deadEye then
        player.deadEyeTimer = 3.0
    end
end

function WeaponRuntime.fireSlot(player, slot_index, aim_x, aim_y)
    local slot = WeaponRuntime.getSlot(player, slot_index)
    if not slot or slot.mode ~= "weapon" or not slot.weapon_def then
        return nil
    end
    if (slot.reload_timer or 0) > 0 or (slot.cooldown_timer or 0) > 0 then
        return nil
    end
    if (slot.ammo or 0) <= 0 then
        WeaponRuntime.startReload(player, slot_index)
        return nil
    end

    local gun = slot.weapon_def
    local resolved = WeaponRuntime.getResolvedStats(player, slot_index)
    local normalized = computeNormalizedStats(player, gun)
    local cx = player.x + player.w / 2
    local cy = player.y + player.h / 2
    local angle = math.atan2(aim_y - cy, aim_x - cx)
    local inaccuracy = resolved and resolved.inaccuracy or 0
    if inaccuracy > 0 then
        angle = angle + (GameRng.randomFloat("player.weapon_inaccuracy." .. tostring(slot_index), 0, 1) - 0.5) * 2 * inaccuracy
    end

    slot.ammo = slot.ammo - 1
    slot.cooldown_timer = resolved and resolved.shootCooldown or 0
    slot.shots_since_reload = (slot.shots_since_reload or 0) + 1

    local profile_id = slot.attack_profile_id or defaultAttackProfileId(gun)
    local profile = ATTACK_PROFILES[profile_id] or ATTACK_PROFILES.projectile_basic
    local bullets = profile({
        player = player,
        slot = slot,
        gun = gun,
        stats = resolved,
        normalized_stats = normalized,
        angle = angle,
        origin_x = cx,
        origin_y = cy,
        source_ref = buildWeaponSourceRef(player, slot),
    })

    if gun.onShoot then
        gun.onShoot(player, angle)
    end

    if slot.ammo <= 0 then
        WeaponRuntime.startReload(player, slot_index)
    else
        WeaponRuntime.syncLegacyViews(player)
    end

    debugDump(player, "fired")
    return {
        bullets = bullets,
        angle = angle,
        weapon_def = gun,
        resolved_stats = resolved,
    }
end

function WeaponRuntime.debugDump(player, reason)
    debugDump(player, reason)
end

return WeaponRuntime
