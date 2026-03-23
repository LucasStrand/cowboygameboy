local RunMetadata = {}

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

function RunMetadata.recordBuildSnapshot(meta, build_snapshot, reason)
    if not meta or not build_snapshot then
        return
    end
    if reason and build_snapshot.snapshot_reason == nil then
        build_snapshot.snapshot_reason = reason
    end
    meta.build_snapshots[#meta.build_snapshots + 1] = build_snapshot
end

function RunMetadata.snapshotBuild(player, build_profile)
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
    bucket.count = #bucket.history
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
    bucket.kills = #bucket.history
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
end

function RunMetadata.finishRun(meta, info)
    if not meta then
        return
    end
    info = info or {}
    meta.run_end = {
        outcome = info.outcome or "completed",
        source = info.source or "run_end",
        level = info.level,
        rooms_cleared = info.rooms_cleared,
        gold = info.gold,
        perks_count = info.perks_count,
        dominant_tags = cloneList(info.dominant_tags),
    }
    RunMetadata.recordBuildSnapshot(meta, info.build_snapshot, info.snapshot_reason or "run_end")
end

return RunMetadata
