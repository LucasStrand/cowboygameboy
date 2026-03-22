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
        },
        shops = {
            generated = {},
            purchased = {},
        },
        economy = {
            gold_earned = 0,
            gold_spent = 0,
            events = {},
        },
        build_snapshots = {},
    }
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
    }
    if build_snapshot then
        meta.build_snapshots[#meta.build_snapshots + 1] = build_snapshot
    end
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
    }
    if build_snapshot then
        meta.build_snapshots[#meta.build_snapshots + 1] = build_snapshot
    end
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

return RunMetadata
