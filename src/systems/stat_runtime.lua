local StatRegistry = require("src.data.stat_registry")
local Weapons = require("src.data.weapons")

local StatRuntime = {}

local function cloneTable(src)
    local out = {}
    for k, v in pairs(src or {}) do
        out[k] = v
    end
    return out
end

local function applyClampAndRounding(id, value)
    local def = StatRegistry.get(id)
    if not def then
        return value
    end
    if def.clamp then
        if def.clamp.min ~= nil and value < def.clamp.min then
            value = def.clamp.min
        end
        if def.clamp.max ~= nil and value > def.clamp.max then
            value = def.clamp.max
        end
    end
    if def.rounding == "floor" and type(value) == "number" then
        value = math.floor(value)
    elseif def.rounding == "ceil" and type(value) == "number" then
        value = math.ceil(value)
    end
    return value
end

local function initStats()
    local stats = {}
    for id, def in pairs(StatRegistry.defs) do
        stats[id] = def.default
    end
    return stats
end

local function normalizeStatMap(map)
    local out = {}
    for key, value in pairs(map or {}) do
        local normalized = StatRegistry.normalizeId(key)
        if normalized then
            out[normalized] = value
        end
    end
    return out
end

local function applyTrace(trace, source_id, stat_id, before, after, op, value)
    trace[#trace + 1] = {
        source_id = source_id,
        stat_id = stat_id,
        before = before,
        after = after,
        op = op,
        value = value,
    }
end

local function applyModifier(stats, trace, source_id, stat_id, op, value)
    local def = StatRegistry.get(stat_id)
    if not def then
        return false, "unknown stat"
    end
    if not StatRegistry.ops[op] then
        return false, "unknown op"
    end

    local accepted = false
    for _, accepted_op in ipairs(def.accepted_ops or {}) do
        if accepted_op == op then
            accepted = true
            break
        end
    end
    if not accepted then
        return false, "op not accepted"
    end

    local before = stats[stat_id]
    local after = before
    if op == "flat" or op == "add_pct" then
        after = before + value
    elseif op == "mul" then
        after = before * value
    elseif op == "override" then
        after = value
    end
    after = applyClampAndRounding(stat_id, after)
    stats[stat_id] = after
    applyTrace(trace, source_id, stat_id, before, after, op, value)
    return true
end

function StatRuntime.validate_modifier(mod)
    if type(mod) ~= "table" then
        return false, "modifier must be a table"
    end
    if not mod.stat then
        return false, "modifier.stat is required"
    end
    local _, normalized = StatRegistry.get(mod.stat)
    if not normalized then
        return false, "unknown stat id: " .. tostring(mod.stat)
    end
    if not mod.op then
        return false, "modifier.op is required"
    end
    if not StatRegistry.ops[mod.op] then
        return false, "unknown op: " .. tostring(mod.op)
    end
    if mod.value == nil then
        return false, "modifier.value is required"
    end
    return true, normalized
end

function StatRuntime.compute_actor_stats(ctx)
    ctx = ctx or {}
    local stats = initStats()
    local trace = {}

    local base_stats = normalizeStatMap(ctx.base_stats)
    for stat_id, value in pairs(base_stats) do
        local before = stats[stat_id]
        stats[stat_id] = applyClampAndRounding(stat_id, value)
        applyTrace(trace, "base_stats", stat_id, before, stats[stat_id], "override", value)
    end

    local function applyStatMap(source_id, map)
        for stat_id, value in pairs(normalizeStatMap(map)) do
            if stats[stat_id] ~= nil and type(stats[stat_id]) == "number" and type(value) == "number" then
                applyModifier(stats, trace, source_id, stat_id, "flat", value)
            elseif stats[stat_id] ~= nil then
                applyModifier(stats, trace, source_id, stat_id, "override", value)
            end
        end
    end

    for source_id, map in pairs(ctx.flat_sources or {}) do
        applyStatMap(source_id, map)
    end

    if ctx.gun and ctx.base_gun_stats then
        local gun_stats = normalizeStatMap(ctx.gun.baseStats or {})
        local base_gun_stats = normalizeStatMap(ctx.base_gun_stats)
        local overridden = {
            magazine_size = true,
            reload_time = true,
            projectile_speed = true,
            projectile_damage = true,
            projectile_count = true,
            spread_angle = true,
        }
        for stat_id in pairs(overridden) do
            local gun_value = gun_stats[stat_id]
            local base_default = base_gun_stats[stat_id]
            local player_value = stats[stat_id]
            if gun_value ~= nil and base_default ~= nil and type(player_value) == "number" then
                local delta = player_value - base_default
                local before = stats[stat_id]
                stats[stat_id] = applyClampAndRounding(stat_id, gun_value + delta)
                applyTrace(trace, "active_gun", stat_id, before, stats[stat_id], "override", gun_value + delta)
            end
        end
        if gun_stats.shoot_cooldown ~= nil then
            local before = stats.shoot_cooldown
            stats.shoot_cooldown = applyClampAndRounding("shoot_cooldown", gun_stats.shoot_cooldown)
            applyTrace(trace, "active_gun", "shoot_cooldown", before, stats.shoot_cooldown, "override", gun_stats.shoot_cooldown)
        end
        if gun_stats.inaccuracy ~= nil then
            local before = stats.inaccuracy
            stats.inaccuracy = applyClampAndRounding("inaccuracy", gun_stats.inaccuracy)
            applyTrace(trace, "active_gun", "inaccuracy", before, stats.inaccuracy, "override", gun_stats.inaccuracy)
        end
    end

    if ctx.gun and ctx.gun.weapon_kind == "melee" and ctx.base_melee_stats then
        local gun_stats = normalizeStatMap(ctx.gun.baseStats or {})
        local base_melee = ctx.base_melee_stats
        local melee_ids = { "melee_damage", "melee_range", "melee_cooldown", "melee_knockback" }
        for _, stat_id in ipairs(melee_ids) do
            local gun_value = gun_stats[stat_id]
            local base_default = base_melee[stat_id]
            local player_value = stats[stat_id]
            if gun_value ~= nil and base_default ~= nil and type(player_value) == "number" then
                local delta = player_value - base_default
                local before = stats[stat_id]
                stats[stat_id] = applyClampAndRounding(stat_id, gun_value + delta)
                applyTrace(trace, "active_melee_weapon", stat_id, before, stats[stat_id], "override", gun_value + delta)
            end
        end
    end

    if ctx.monster_move_bonus and ctx.monster_move_bonus ~= 0 then
        applyModifier(stats, trace, "monster_energy", "move_speed", "flat", ctx.monster_move_bonus)
    end

    return stats, trace
end

function StatRuntime.export_legacy_stats(final_stats)
    local legacy = {}
    local inverse_alias = {}
    for alias, normalized in pairs(StatRegistry.legacy_aliases) do
        inverse_alias[normalized] = inverse_alias[normalized] or {}
        inverse_alias[normalized][#inverse_alias[normalized] + 1] = alias
    end

    for stat_id, value in pairs(final_stats or {}) do
        local aliases = inverse_alias[stat_id]
        if aliases then
            for _, alias in ipairs(aliases) do
                legacy[alias] = value
            end
        end
    end
    return legacy
end

function StatRuntime.build_enemy_offense_context(enemy, profile)
    local flat_sources = {}
    if enemy and enemy.statuses then
        local Buffs = require("src.systems.buffs")
        local mods = Buffs.getStatMods(enemy.statuses)
        flat_sources.buffs = normalizeStatMap(mods)
    end

    local base_stats = {}
    if profile and type(profile.offensive_stats) == "table" then
        base_stats = normalizeStatMap(profile.offensive_stats)
    end

    return {
        base_stats = base_stats,
        flat_sources = flat_sources,
    }
end

function StatRuntime.build_player_context(player, gun, base_gun_stats)
    local flat_sources = {}
    for slot, gear in pairs(player.gear or {}) do
        if gear and gear.stats then
            if slot ~= "melee" and slot ~= "shield" then
                flat_sources["gear_" .. slot] = cloneTable(gear.stats)
            elseif slot == "shield" then
                flat_sources["gear_" .. slot] = cloneTable(gear.stats)
            end
        end
    end

    -- Unarmed fist stats when no melee weapon is active; knife uses weapon slot + active_melee_weapon merge.
    if not (gun and gun.weapon_kind == "melee") then
        if Weapons.defaults.unarmed and Weapons.defaults.unarmed.stats then
            flat_sources.unarmed_melee = cloneTable(Weapons.defaults.unarmed.stats)
        end
    end

    local buff_mods = nil
    local status_tracker = player.statuses or player.buffs
    if status_tracker then
        local Buffs = require("src.systems.buffs")
        buff_mods = Buffs.getStatMods(status_tracker)
    end
    if buff_mods then
        flat_sources.buffs = cloneTable(buff_mods)
    end

    return {
        base_stats = cloneTable(player.stats or {}),
        flat_sources = flat_sources,
        gun = gun,
        base_gun_stats = base_gun_stats,
        base_melee_stats = normalizeStatMap(Weapons.defaults.unarmed and Weapons.defaults.unarmed.stats or {}),
        monster_move_bonus = player.monsterMoveBonus or 0,
    }
end

return StatRuntime
