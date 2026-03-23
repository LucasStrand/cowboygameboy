local RunMetadata = {}

-- Phase 10: bounded retention (documented in docs/phases/phase_10_hardening.md)
RunMetadata.RECAP_EXPORT_VERSION = 1
RunMetadata.METADATA_RETENTION_VERSION = 1

local MAX_DAMAGE_EVENTS_DEALT = 240
local MAX_DAMAGE_TO_PLAYER_EVENTS = 120
local MAX_ECONOMY_EVENTS = 400
local MAX_BUILD_SNAPSHOTS = 120
local MAX_ROOMS_RECORDED = 400
local MAX_REWARDS_OFFERED = 160
local MAX_REWARDS_CHOSEN = 100
local MAX_SHOPS_GENERATED = 100
local MAX_SHOPS_PURCHASED = 160
local MAX_SHOP_VISITS = 120
local MAX_REROLL_HISTORY = 80
local MAX_CHECKPOINT_HISTORY = 120
local MAX_BOSS_KILL_HISTORY = 64

local function trimArrayFront(arr, maxN)
    if not arr or not maxN then
        return
    end
    while #arr > maxN do
        table.remove(arr, 1)
    end
end

local function shallowCopy(value)
    local out = {}
    for k, v in pairs(value or {}) do
        out[k] = v
    end
    return out
end

local function cloneList(list)
    local out = {}
    for i, value in ipairs(list or {}) do
        out[i] = value
    end
    return out
end

local function defaultDamageBreakdown()
    return {
        melee = 0,
        ultimate = 0,
        explosion = 0,
        proc = 0,
        physical = 0,
        magical = 0,
        true_damage = 0,
    }
end

local function cloneDamageEvent(event)
    return {
        amount = tonumber(event and event.amount or 0) or 0,
        source_type = event and event.source_type or "unknown",
        source_id = event and event.source_id or "unknown",
        parent_source_id = event and event.parent_source_id or nil,
        packet_kind = event and event.packet_kind or "unknown",
        family = event and event.family or "unknown",
        target_id = event and event.target_id or "unknown",
        room_id = event and event.room_id or nil,
        room_name = event and event.room_name or nil,
        room_index = event and event.room_index or nil,
        world_id = event and event.world_id or nil,
        world_name = event and event.world_name or nil,
        tags = cloneList(event and event.tags or {}),
    }
end

--- Damage taken by the player (incoming); separate from damage_events (dealt to enemies).
local function cloneIncomingDamageSnapshot(detail)
    if not detail then
        return nil
    end
    local out = {
        amount = tonumber(detail.amount or 0) or 0,
        source_type = detail.source_type or "unknown",
        source_id = detail.source_id or "unknown",
        parent_source_id = detail.parent_source_id or nil,
        packet_kind = detail.packet_kind or "unknown",
        family = detail.family or "unknown",
        target_id = detail.target_id or "unknown",
        source_name = detail.source_name or nil,
        enemy_type_id = detail.enemy_type_id or nil,
        room_id = detail.room_id or nil,
        room_name = detail.room_name or nil,
        room_index = detail.room_index or nil,
        world_id = detail.world_id or nil,
        world_name = detail.world_name or nil,
        tags = cloneList(detail.tags or {}),
    }
    return out
end

local function ensureCombat(meta)
    if not meta then
        return nil
    end
    local combat = meta.combat
    if not combat then
        combat = {}
        meta.combat = combat
    end
    combat.total_damage_dealt = combat.total_damage_dealt or 0
    combat.breakdown = combat.breakdown or defaultDamageBreakdown()
    combat.damage_events = combat.damage_events or {}
    combat.damage_to_player_events = combat.damage_to_player_events or {}
    return combat
end

local function cloneDamageBreakdown(breakdown)
    local out = defaultDamageBreakdown()
    for key, value in pairs(breakdown or {}) do
        if type(value) == "number" then
            out[key] = value
        end
    end
    return out
end

function RunMetadata.new(seed, context)
    context = context or {}
    return {
        seed = seed,
        route = {
            world_id = context.world_id,
            world_name = context.world_name,
            dev_arena = context.dev_arena == true,
        },
        rooms = {},
        rewards = {
            offered = {},
            chosen = {},
            rerolls = {
                count = 0,
                history = {},
            },
        },
        shops = {
            generated = {},
            purchased = {},
            rerolls = {
                count = 0,
                history = {},
            },
            visits = {},
        },
        economy = {
            gold_earned = 0,
            gold_spent = 0,
            events = {},
            reroll_counts = {
                levelup = 0,
                shop = 0,
            },
        },
        combat = {
            total_damage_dealt = 0,
            breakdown = defaultDamageBreakdown(),
            damage_events = {},
            damage_to_player_events = {},
        },
        milestones = {
            checkpoints = {
                count = 0,
                history = {},
            },
            bosses = {
                kills = 0,
                history = {},
                seen_actor_ids = {},
            },
        },
        build_snapshots = {},
        run_end = nil,
    }
end

function RunMetadata.recordDamageToPlayer(meta, detail)
    if not meta or not detail then
        return
    end
    local amt = tonumber(detail.amount or 0) or 0
    if amt <= 0 then
        return
    end
    local combat = ensureCombat(meta)
    local snap = cloneIncomingDamageSnapshot(detail)
    combat.last_damage_to_player = snap
    local ev = combat.damage_to_player_events
    ev[#ev + 1] = snap
    trimArrayFront(ev, MAX_DAMAGE_TO_PLAYER_EVENTS)
end

function RunMetadata.recordMajorProc(meta, info)
    if not meta or not info then
        return
    end
    local combat = ensureCombat(meta)
    combat.last_major_proc = {
        perk_id = info.perk_id,
        rule_id = info.rule_id,
        damage = tonumber(info.damage or 0) or 0,
    }
end

function RunMetadata.recordDamageDealt(meta, amount, breakdown, detail)
    if not meta or type(amount) ~= "number" or amount <= 0 then
        return
    end
    local combat = ensureCombat(meta)
    combat.total_damage_dealt = (combat.total_damage_dealt or 0) + amount
    local bucket = combat.breakdown or defaultDamageBreakdown()
    combat.breakdown = bucket
    for key, enabled in pairs(breakdown or {}) do
        if enabled then
            bucket[key] = (bucket[key] or 0) + amount
        end
    end
    if detail then
        local events = combat.damage_events
        events[#events + 1] = cloneDamageEvent(detail)
        trimArrayFront(events, MAX_DAMAGE_EVENTS_DEALT)
    end
end

--- Counts vs caps for dev / Phase 10 diagnostics (not persisted).
function RunMetadata.retentionStats(meta)
    if not meta then
        return { note = "no metadata" }
    end
    local c = meta.combat or {}
    local e = meta.economy or {}
    local ms = meta.milestones or {}
    local cp = ms.checkpoints or {}
    local bs = ms.bosses or {}
    return {
        retention_policy_version = RunMetadata.METADATA_RETENTION_VERSION,
        damage_events = #(c.damage_events or {}),
        damage_events_cap = MAX_DAMAGE_EVENTS_DEALT,
        damage_to_player_events = #(c.damage_to_player_events or {}),
        damage_to_player_cap = MAX_DAMAGE_TO_PLAYER_EVENTS,
        economy_events = #(e.events or {}),
        economy_events_cap = MAX_ECONOMY_EVENTS,
        rooms = #(meta.rooms or {}),
        rooms_cap = MAX_ROOMS_RECORDED,
        build_snapshots = #(meta.build_snapshots or {}),
        build_snapshots_cap = MAX_BUILD_SNAPSHOTS,
        rewards_offered = #(meta.rewards and meta.rewards.offered or {}),
        rewards_offered_cap = MAX_REWARDS_OFFERED,
        rewards_chosen = #(meta.rewards and meta.rewards.chosen or {}),
        rewards_chosen_cap = MAX_REWARDS_CHOSEN,
        shops_generated = #(meta.shops and meta.shops.generated or {}),
        shops_generated_cap = MAX_SHOPS_GENERATED,
        shops_purchased = #(meta.shops and meta.shops.purchased or {}),
        shops_purchased_cap = MAX_SHOPS_PURCHASED,
        shop_visits = #(meta.shops and meta.shops.visits or {}),
        shop_visits_cap = MAX_SHOP_VISITS,
        checkpoint_history = #(cp.history or {}),
        checkpoint_history_cap = MAX_CHECKPOINT_HISTORY,
        boss_kill_history = #(bs.history or {}),
        boss_kill_history_cap = MAX_BOSS_KILL_HISTORY,
    }
end

function RunMetadata.recordBuildSnapshot(meta, build_snapshot, reason)
    if not meta or not build_snapshot then
        return
    end
    if reason and build_snapshot.snapshot_reason == nil then
        build_snapshot.snapshot_reason = reason
    end
    meta.build_snapshots[#meta.build_snapshots + 1] = build_snapshot
    trimArrayFront(meta.build_snapshots, MAX_BUILD_SNAPSHOTS)
end

function RunMetadata.snapshotBuild(player, build_profile)
    local effective_stats = player and player.getEffectiveStats and player:getEffectiveStats() or {}
    local weapons = {}
    for slot_index = 1, 2 do
        local slot = player and player.weapons and player.weapons[slot_index] or nil
        local gun = slot and slot.gun or nil
        weapons[#weapons + 1] = {
            slot = slot_index,
            gun_id = gun and gun.id or nil,
        }
    end

    local gear = {}
    for _, slot in ipairs({ "hat", "vest", "boots", "melee", "shield" }) do
        local item = player and player.gear and player.gear[slot] or nil
        gear[#gear + 1] = {
            slot = slot,
            gear_id = item and item.id or nil,
        }
    end

    return {
        level = player and player.level or nil,
        gold = player and player.gold or nil,
        stats = {
            max_hp = effective_stats.maxHP,
            armor = effective_stats.armor,
            luck_pct = type(effective_stats.luck) == "number" and math.floor(effective_stats.luck * 100 + 0.5) or nil,
            bullet_damage = effective_stats.bulletDamage,
            damage_multiplier_pct = type(effective_stats.damageMultiplier) == "number"
                and math.floor((effective_stats.damageMultiplier - 1) * 100 + 0.5)
                or nil,
            crit_chance_pct = type(effective_stats.critChance) == "number"
                and math.floor(effective_stats.critChance * 100 + 0.5)
                or nil,
            move_speed = effective_stats.moveSpeed,
        },
        perks = cloneList(player and player.perks or {}),
        weapons = weapons,
        gear = gear,
        build_profile = build_profile and {
            weapon_family = build_profile.weapon_family,
            damage_theme = build_profile.damage_theme,
            status_theme = build_profile.status_theme,
            dominant_tags = cloneList(build_profile.dominant_tags),
            tag_weights = shallowCopy(build_profile.tag_weights),
        } or nil,
    }
end

function RunMetadata.recordRoom(meta, room, extra)
    if not meta then
        return
    end
    extra = extra or {}
    meta.rooms[#meta.rooms + 1] = {
        id = room and room.id or extra.id,
        name = room and room.name or extra.name,
        world_id = extra.world_id,
        room_index = extra.room_index,
        total_cleared = extra.total_cleared,
        difficulty = extra.difficulty,
        boss_fight = room and room.bossFight or extra.boss_fight,
        dev_arena = extra.dev_arena == true,
    }
    trimArrayFront(meta.rooms, MAX_ROOMS_RECORDED)
end

function RunMetadata.recordRewardOffered(meta, source, offers, build_snapshot)
    if not meta then
        return
    end
    meta.rewards.offered[#meta.rewards.offered + 1] = {
        source = source,
        offers = cloneList(offers),
        build_snapshot = build_snapshot,
        gold_before = build_snapshot and build_snapshot.gold or nil,
    }
    trimArrayFront(meta.rewards.offered, MAX_REWARDS_OFFERED)
end

function RunMetadata.recordRewardChosen(meta, source, chosen, offers, build_snapshot)
    if not meta then
        return
    end
    meta.rewards.chosen[#meta.rewards.chosen + 1] = {
        source = source,
        chosen = chosen,
        offers = cloneList(offers),
        build_snapshot = build_snapshot,
        gold_after = build_snapshot and build_snapshot.gold or nil,
    }
    RunMetadata.recordBuildSnapshot(meta, build_snapshot, "reward_choice")
    trimArrayFront(meta.rewards.chosen, MAX_REWARDS_CHOSEN)
end

function RunMetadata.recordShopGenerated(meta, offers, build_snapshot, extra)
    if not meta then
        return
    end
    extra = extra or {}
    meta.shops.generated[#meta.shops.generated + 1] = {
        difficulty = extra.difficulty,
        source = extra.source or "shop",
        offers = cloneList(offers),
        build_snapshot = build_snapshot,
        gold_before = build_snapshot and build_snapshot.gold or nil,
    }
    trimArrayFront(meta.shops.generated, MAX_SHOPS_GENERATED)
end

function RunMetadata.recordShopPurchased(meta, item, build_snapshot, extra)
    if not meta then
        return
    end
    extra = extra or {}
    meta.shops.purchased[#meta.shops.purchased + 1] = {
        id = item and item.id or nil,
        name = item and item.name or nil,
        price = extra.price,
        type = item and item.type or nil,
        reward_bucket = item and item.reward_bucket or nil,
        reward_role = item and item.reward_role or nil,
        build_snapshot = build_snapshot,
        gold_after = build_snapshot and build_snapshot.gold or nil,
    }
    RunMetadata.recordBuildSnapshot(meta, build_snapshot, "shop_purchase")
    trimArrayFront(meta.shops.purchased, MAX_SHOPS_PURCHASED)
end

function RunMetadata.recordEconomy(meta, kind, amount, reason)
    if not meta or type(amount) ~= "number" or amount == 0 then
        return
    end
    meta.economy.events[#meta.economy.events + 1] = {
        kind = kind,
        amount = amount,
        reason = reason,
    }
    if kind == "earned" then
        meta.economy.gold_earned = meta.economy.gold_earned + amount
    elseif kind == "spent" then
        meta.economy.gold_spent = meta.economy.gold_spent + amount
    end
    trimArrayFront(meta.economy.events, MAX_ECONOMY_EVENTS)
end

function RunMetadata.recordShopVisit(meta, info)
    if not meta then
        return
    end
    info = info or {}
    meta.shops.visits[#meta.shops.visits + 1] = {
        source = info.source or "shop_visit",
        difficulty = info.difficulty,
        gold_before = info.gold_before,
        gold_after = info.gold_after,
    }
    trimArrayFront(meta.shops.visits, MAX_SHOP_VISITS)
end

function RunMetadata.recordCheckpoint(meta, info)
    if not meta then
        return
    end
    info = info or {}
    local bucket = meta.milestones and meta.milestones.checkpoints
    if not bucket then
        return
    end
    bucket.history[#bucket.history + 1] = {
        world_id = info.world_id,
        world_name = info.world_name,
        room_index = info.room_index,
        total_cleared = info.total_cleared,
        difficulty = info.difficulty,
        dev_arena = info.dev_arena == true,
    }
    bucket.count = (bucket.count or 0) + 1
    trimArrayFront(bucket.history, MAX_CHECKPOINT_HISTORY)
end

function RunMetadata.recordBossKilled(meta, enemy, info)
    if not meta then
        return
    end
    info = info or {}
    local bucket = meta.milestones and meta.milestones.bosses
    if not bucket then
        return
    end
    local actor_id = enemy and enemy.actorId or info.actor_id
    if actor_id and bucket.seen_actor_ids and bucket.seen_actor_ids[actor_id] then
        return
    end
    if actor_id and bucket.seen_actor_ids then
        bucket.seen_actor_ids[actor_id] = true
    end
    bucket.history[#bucket.history + 1] = {
        actor_id = actor_id,
        enemy_id = enemy and enemy.typeId or info.enemy_id,
        enemy_name = enemy and enemy.name or info.enemy_name,
        room_id = info.room_id,
        room_name = info.room_name,
        world_id = info.world_id,
        world_name = info.world_name,
        room_index = info.room_index,
        total_cleared = info.total_cleared,
        difficulty = info.difficulty,
        dev_arena = info.dev_arena == true,
    }
    bucket.kills = (bucket.kills or 0) + 1
    trimArrayFront(bucket.history, MAX_BOSS_KILL_HISTORY)
end

function RunMetadata.getRerollCount(meta, surface)
    if not meta then
        return 0
    end
    if surface == "shop" then
        return meta.shops and meta.shops.rerolls and meta.shops.rerolls.count or 0
    end
    return meta.rewards and meta.rewards.rerolls and meta.rewards.rerolls.count or 0
end

function RunMetadata.recordReroll(meta, surface, cost, before_offers, after_offers, build_snapshot)
    if not meta then
        return
    end
    local bucket = surface == "shop" and meta.shops.rerolls or meta.rewards.rerolls
    bucket.count = (bucket.count or 0) + 1
    bucket.history[#bucket.history + 1] = {
        cost = cost,
        before = cloneList(before_offers),
        after = cloneList(after_offers),
        build_snapshot = build_snapshot,
        gold_after = build_snapshot and build_snapshot.gold or nil,
    }
    meta.economy.reroll_counts[surface == "shop" and "shop" or "levelup"] =
        (meta.economy.reroll_counts[surface == "shop" and "shop" or "levelup"] or 0) + 1
    trimArrayFront(bucket.history, MAX_REROLL_HISTORY)
end

function RunMetadata.finishRun(meta, info)
    if not meta then
        return
    end
    info = info or {}
    local combat = ensureCombat(meta)
    local last_in = combat.last_damage_to_player
    local last_proc = combat.last_major_proc
    local dealt = combat.damage_events or {}
    local first_dealt = dealt[1]
    local last_dealt = dealt[#dealt]
    meta.run_end = {
        outcome = info.outcome or "completed",
        source = info.source or "run_end",
        level = info.level,
        rooms_cleared = info.rooms_cleared,
        gold = info.gold,
        perks_count = info.perks_count,
        total_damage_dealt = info.total_damage_dealt or combat.total_damage_dealt or 0,
        damage_breakdown = cloneDamageBreakdown(info.damage_breakdown or combat.breakdown),
        dominant_tags = cloneList(info.dominant_tags),
        recap_outcome = info.outcome or "completed",
        last_damage_to_player = last_in and cloneIncomingDamageSnapshot(last_in) or nil,
        last_major_proc = last_proc
            and {
                perk_id = last_proc.perk_id,
                rule_id = last_proc.rule_id,
                damage = tonumber(last_proc.damage or 0) or 0,
            }
            or nil,
        visible_buff_count = info.visible_buff_count,
        damage_trace_primary_source = first_dealt
            and table.concat({
                tostring(first_dealt.source_type or "?"),
                tostring(first_dealt.source_id or "?"),
                tostring(first_dealt.family or "?"),
            }, " / ")
            or nil,
        damage_trace_last_event_source = last_dealt
            and table.concat({
                tostring(last_dealt.source_type or "?"),
                tostring(last_dealt.source_id or "?"),
                tostring(last_dealt.family or "?"),
            }, " / ")
            or nil,
        damage_trace_last_incoming_source = last_in
            and table.concat({
                tostring(last_in.source_type or "?"),
                tostring(last_in.source_id or "?"),
                tostring(last_in.family or "?"),
            }, " / ")
            or nil,
    }
    RunMetadata.recordBuildSnapshot(meta, info.build_snapshot, info.snapshot_reason or "run_end")
end

return RunMetadata
