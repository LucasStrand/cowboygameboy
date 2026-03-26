local GameRng = require("src.systems.game_rng")
local RunMetadata = require("src.systems.run_metadata")

local Perks = require("src.data.perks")
local GearData = require("src.data.gear")
local Guns = require("src.data.guns")
local Weapons = require("src.data.weapons")

local RewardRuntime = {}
local REROLL_BASE_COST = {
    levelup = 18,
    shop = 32,
}
local REROLL_STEP_COST = {
    levelup = 12,
    shop = 18,
}

local FEATURE_HINTS = {
    damage_up = { "theme:damage" },
    speed_up = { "theme:mobility" },
    hp_up = { "theme:defense" },
    armor_up = { "theme:defense" },
    fast_reload = { "theme:reload" },
    extra_bullet = { "theme:ammo" },
    lifesteal = { "theme:sustain" },
    luck_up = { "theme:luck" },
    scattershot = { "theme:multishot" },
    explosive_rounds = { "theme:explosive", "damage:aoe" },
    ricochet = { "theme:ricochet" },
    akimbo = { "theme:multishot" },
    phantom_third = { "theme:proc", "damage:true" },
    cowboy_hat = { "theme:luck" },
    ten_gallon = { "theme:luck", "theme:defense" },
    sheriffs_hat = { "theme:luck", "theme:defense" },
    leather_vest = { "theme:defense" },
    reinforced_vest = { "theme:defense" },
    bandolier = { "theme:damage", "attack:projectile" },
    riding_boots = { "theme:mobility" },
    spurred_boots = { "theme:mobility", "theme:damage" },
    snake_boots = { "theme:mobility", "theme:luck" },
    knife = { "attack:melee", "theme:damage" },
    heal = { "theme:sustain" },
    ammo_upgrade = { "theme:ammo", "attack:projectile" },
}

local function shallowCopy(value)
    local out = {}
    for k, v in pairs(value or {}) do
        out[k] = v
    end
    return out
end

local function listHas(list, wanted)
    for _, value in ipairs(list or {}) do
        if value == wanted then
            return true
        end
    end
    return false
end

local function addTag(tag_weights, tag, amount)
    if not tag then
        return
    end
    tag_weights[tag] = (tag_weights[tag] or 0) + (amount or 1)
end

local function addTags(tag_weights, tags, amount)
    for _, tag in ipairs(tags or {}) do
        addTag(tag_weights, tag, amount)
    end
end

local function firstTagForPrefix(tags, prefix)
    local wanted = prefix .. ":"
    for _, tag in ipairs(tags or {}) do
        if tag:sub(1, #wanted) == wanted then
            return tag
        end
    end
end

local function collectItemTags(item)
    local tags = {}
    local seen = {}
    local function append(tag)
        if type(tag) == "string" and not seen[tag] then
            seen[tag] = true
            tags[#tags + 1] = tag
        end
    end

    for _, tag in ipairs(item.tags or {}) do
        append(tag)
    end
    for _, tag in ipairs(FEATURE_HINTS[item.id] or {}) do
        append(tag)
    end

    local stats = item.stats or item.baseStats or {}
    if type(stats.bulletCount) == "number" and stats.bulletCount > 1 then
        append("theme:multishot")
        append("attack:projectile")
    end
    if type(stats.reloadSpeed) == "number" and stats.reloadSpeed < 1 then
        append("theme:reload")
    end
    if type(stats.cylinderSize) == "number" and stats.cylinderSize > 6 then
        append("theme:ammo")
    end
    if type(stats.moveSpeed) == "number" and stats.moveSpeed > 0 then
        append("theme:mobility")
    end
    if type(stats.maxHP) == "number" and stats.maxHP > 0 then
        append("theme:defense")
    end
    if type(stats.armor) == "number" and stats.armor > 0 then
        append("theme:defense")
    end
    if type(stats.damageMultiplier) == "number" and stats.damageMultiplier > 0 then
        append("theme:damage")
    end
    if type(stats.damage) == "number" and stats.damage > 0 then
        append("theme:damage")
    end
    if type(stats.meleeDamage) == "number" and stats.meleeDamage > 0 then
        append("attack:melee")
        append("theme:damage")
    end
    if type(stats.luck) == "number" and stats.luck > 0 then
        append("theme:luck")
    end

    return tags
end

local function topTag(tag_weights, prefix)
    local best_tag, best_weight = nil, -math.huge
    local wanted = prefix .. ":"
    for tag, weight in pairs(tag_weights or {}) do
        if tag:sub(1, #wanted) == wanted and weight > best_weight then
            best_tag = tag
            best_weight = weight
        end
    end
    return best_tag and best_tag:sub(#wanted + 1) or nil
end

local function sortedDominantTags(tag_weights, count)
    local items = {}
    for tag, weight in pairs(tag_weights or {}) do
        if weight > 0 and tag:match("^(weapon|damage|status|theme|setup|attack):") then
            items[#items + 1] = { tag = tag, weight = weight }
        end
    end
    table.sort(items, function(a, b)
        if a.weight == b.weight then
            return a.tag < b.tag
        end
        return a.weight > b.weight
    end)
    local out = {}
    for i = 1, math.min(count or 4, #items) do
        out[#out + 1] = items[i].tag
    end
    return out
end

local function buildReason(profile, candidate_tags, overlap_score)
    local matches = {}
    for _, tag in ipairs(candidate_tags or {}) do
        if (profile.tag_weights[tag] or 0) > 0 then
            matches[#matches + 1] = tag
        end
    end
    if #matches > 0 then
        return string.format("matches %s (score %.1f)", table.concat(matches, ", "), overlap_score)
    end
    local pivot_tag = firstTagForPrefix(candidate_tags, "theme") or firstTagForPrefix(candidate_tags, "damage")
    if pivot_tag then
        return "opens " .. pivot_tag
    end
    return "stable fallback"
end

local function bucketForCandidate(profile, item, candidate_tags)
    local explicit_bucket = firstTagForPrefix(candidate_tags, "reward")
    if explicit_bucket then
        return explicit_bucket:sub(8)
    end

    local overlap_score = 0
    for _, tag in ipairs(candidate_tags or {}) do
        overlap_score = overlap_score + math.min(2, profile.tag_weights[tag] or 0)
    end
    if overlap_score >= 2 then
        return "support"
    end
    if overlap_score <= 0 and (#candidate_tags > 0) then
        return "pivot"
    end
    return "neutral"
end

local function decorateCandidate(profile, item, fallback_role)
    local candidate = shallowCopy(item)
    local tags = collectItemTags(item)
    local overlap_score = 0
    for _, tag in ipairs(tags) do
        overlap_score = overlap_score + math.min(2, profile.tag_weights[tag] or 0)
    end
    local reward_bucket = bucketForCandidate(profile, item, tags)
    local reward_role = firstTagForPrefix(tags, "role")
    candidate.reward_bucket = reward_bucket
    candidate.reward_role = reward_role and reward_role:sub(6) or fallback_role
    candidate.reward_reason = buildReason(profile, tags, overlap_score)
    candidate.reward_tags = tags
    candidate.reward_score = overlap_score
    return candidate
end

local function randomWeightedChoice(prefix, candidates, generation_index)
    local total_weight = 0
    for _, candidate in ipairs(candidates) do
        total_weight = total_weight + math.max(0.01, candidate.reward_weight or candidate.weight or 1)
    end
    if total_weight <= 0 then
        return nil
    end
    local roll = GameRng.randomFloat(prefix .. ".weight." .. tostring(generation_index), 0, total_weight)
    local cumulative = 0
    for _, candidate in ipairs(candidates) do
        cumulative = cumulative + math.max(0.01, candidate.reward_weight or candidate.weight or 1)
        if roll <= cumulative then
            return candidate
        end
    end
    return candidates[#candidates]
end

local function buildGenerationIndex(context, source)
    local meta = context and context.run_metadata or nil
    if source == "levelup" then
        return meta and (#meta.rewards.offered + 1) or 1
    end
    return meta and (#meta.shops.generated + 1) or 1
end

local function normalizeSurface(surface)
    if surface == "shop" or surface == "saloon_shop" or surface == "dev_arena_shop" then
        return "shop"
    end
    return "levelup"
end

local function pickWithoutDuplicates(prefix, all_candidates, wanted_bucket, picked_ids, generation_index)
    local bucket_pool = {}
    local fallback_pool = {}
    for _, candidate in ipairs(all_candidates) do
        if not picked_ids[candidate.id] then
            fallback_pool[#fallback_pool + 1] = candidate
            if candidate.reward_bucket == wanted_bucket then
                bucket_pool[#bucket_pool + 1] = candidate
            end
        end
    end
    local pool = (#bucket_pool > 0) and bucket_pool or fallback_pool
    local chosen = randomWeightedChoice(prefix, pool, generation_index)
    if chosen then
        picked_ids[chosen.id] = true
    end
    return chosen
end

function RewardRuntime.buildProfile(player, context)
    local tag_weights = {}
    local context_ = context or {}

    for slot_index = 1, 2 do
        local slot = player and player.weapons and player.weapons[slot_index] or nil
        local gun = slot and slot.gun or nil
        if gun then
            addTags(tag_weights, collectItemTags(gun), 3)
        end
    end

    for _, perk_id in ipairs(player and player.perks or {}) do
        local perk = Perks.getById(perk_id)
        if perk then
            addTags(tag_weights, collectItemTags(perk), 2)
        end
    end

    for _, slot_name in ipairs({ "hat", "vest", "boots", "melee", "shield" }) do
        local gear = player and player.gear and player.gear[slot_name] or nil
        if gear then
            addTags(tag_weights, collectItemTags(gear), 1)
        end
    end

    local profile = {
        source = context_.source or "reward_runtime",
        tag_weights = tag_weights,
        weapon_family = topTag(tag_weights, "weapon") or "revolver",
        damage_theme = topTag(tag_weights, "damage") or topTag(tag_weights, "theme") or "direct",
        status_theme = topTag(tag_weights, "status") or "none",
        dominant_tags = sortedDominantTags(tag_weights, 4),
    }
    return profile
end

function RewardRuntime.describeProfile(profile)
    local tags = profile and profile.dominant_tags or {}
    return string.format(
        "weapon=%s | damage=%s | status=%s | tags=%s",
        tostring(profile and profile.weapon_family or "none"),
        tostring(profile and profile.damage_theme or "none"),
        tostring(profile and profile.status_theme or "none"),
        (#tags > 0) and table.concat(tags, ", ") or "none"
    )
end

function RewardRuntime.getRerollCost(surface, run_meta, context)
    local normalized = normalizeSurface(surface)
    local reroll_count = RunMetadata.getRerollCount(run_meta, normalized)
    local base = REROLL_BASE_COST[normalized] or 20
    local step = REROLL_STEP_COST[normalized] or 10
    local cost = base + reroll_count * step
    if normalized == "shop" then
        local difficulty = context and context.difficulty or 1
        cost = cost + math.max(0, math.floor((difficulty - 1) * 4))
    end
    return cost
end

local function buildPerkCandidates(player, profile)
    local owned = {}
    for _, perk_id in ipairs(player and player.perks or {}) do
        owned[perk_id] = true
    end
    local candidates = {}
    for _, perk in ipairs(Perks.pool) do
        if not owned[perk.id] then
            local candidate = decorateCandidate(profile, perk, "power")
            candidate.reward_weight = perk.weight or 1
            if candidate.reward_bucket == "support" then
                candidate.reward_weight = candidate.reward_weight + 3
            elseif candidate.reward_bucket == "pivot" then
                candidate.reward_weight = candidate.reward_weight + 1
            end
            candidates[#candidates + 1] = candidate
        end
    end
    return candidates
end

function RewardRuntime.rollLevelUpChoices(player, context)
    context = context or {}
    local generation_index = buildGenerationIndex(context, "levelup")
    local offer_source = context.source or "levelup"
    local profile = RewardRuntime.buildProfile(player, { source = offer_source })
    local candidates = buildPerkCandidates(player, profile)
    local picked = {}
    local offers = {}

    for slot_index, bucket in ipairs({ "support", "neutral", "pivot" }) do
        local chosen = pickWithoutDuplicates("reward.levelup." .. bucket, candidates, bucket, picked, generation_index + slot_index)
        if chosen then
            offers[#offers + 1] = chosen
        end
    end

    local meta = context and context.run_metadata or nil
    if meta then
        RunMetadata.recordRewardOffered(meta, offer_source, offers, RunMetadata.snapshotBuild(player, profile))
    end

    return offers, profile
end

local function buildGearCandidates(player, profile, max_tier)
    local equipped = {}
    for _, slot_name in ipairs({ "hat", "vest", "boots" }) do
        local gear = player and player.gear and player.gear[slot_name] or nil
        if gear and gear.id then
            equipped[gear.id] = true
        end
    end

    local candidates = {}
    for _, gear in ipairs(GearData.pool or {}) do
        if gear.tier <= max_tier and not equipped[gear.id] then
            local candidate = decorateCandidate(profile, gear, "power")
            candidate.type = "gear"
            candidate.gearData = gear
            candidate.tooltip_key = gear.tooltip_key
            candidate.tooltip_tokens = gear.tooltip_tokens
            candidate.reward_weight = math.max(1, 5 - gear.tier)
            if candidate.reward_bucket == "support" then
                candidate.reward_weight = candidate.reward_weight + 4
            end
            candidates[#candidates + 1] = candidate
        end
    end

    -- Knife (melee weapon): same shop/equip path as hat/vest/boots; only if slot is empty.
    -- Lazy-require Combat here — top-level require would cycle: combat → hud → reward_runtime → combat.
    local meleeEquipped = player and player.gear and player.gear.melee
    if not meleeEquipped and Weapons.defaults.melee then
        local knife = Weapons.defaults.melee
        if knife.tier <= max_tier then
            local Combat = require("src.systems.combat")
            local candidate = decorateCandidate(profile, knife, "power")
            candidate.type = "gear"
            candidate.gearData = Combat.cloneMeleeGearDef(knife)
            candidate.tooltip_key = knife.tooltip_key
            candidate.tooltip_tokens = knife.tooltip_tokens
            candidate.reward_weight = math.max(1, 5 - (knife.tier or 1))
            if candidate.reward_bucket == "support" then
                candidate.reward_weight = candidate.reward_weight + 4
            end
            candidates[#candidates + 1] = candidate
        end
    end

    return candidates
end

local function buildOfferCandidate(profile, template, fallback_role)
    local candidate = decorateCandidate(profile, template, fallback_role)
    candidate.reward_weight = 1
    return candidate
end

function RewardRuntime.rollShopOffers(player, context)
    context = context or {}
    local generation_index = buildGenerationIndex(context, "shop")
    local profile = RewardRuntime.buildProfile(player, { source = "shop" })
    local difficulty = context.difficulty or 1
    local max_tier = math.min(3, math.floor(difficulty / 2) + 1)
    local price_multiplier = 1 + (difficulty - 1) * 0.18

    local function priceForOffer(item)
        local role = item.reward_role or item.type or "utility"
        local bucket = item.reward_bucket or "neutral"
        if role == "sustain" or item.type == "heal" then
            return math.floor(46 * price_multiplier)
        elseif role == "utility" or item.type == "ammo" then
            return math.floor(28 * price_multiplier)
        end
        local tier = item.gearData and item.gearData.tier or 1
        if bucket == "pivot" then
            return math.floor((42 + tier * 14) * price_multiplier)
        end
        return math.floor((54 + tier * 18) * price_multiplier)
    end

    local Shop = require("src.systems.shop")
    local heal = buildOfferCandidate(profile, Shop.offer_templates.heal, "sustain")
    heal.price = priceForOffer(heal)
    heal.type = "heal"
    heal.sold = false

    local ammo = buildOfferCandidate(profile, Shop.offer_templates.ammo_upgrade, "utility")
    ammo.price = priceForOffer(ammo)
    ammo.type = "ammo"
    ammo.sold = false

    local gear_candidates = buildGearCandidates(player, profile, max_tier)
    local picked = {}
    local support_gear = pickWithoutDuplicates("reward.shop.gear.support", gear_candidates, "support", picked, generation_index + 1)
    local pivot_gear = pickWithoutDuplicates("reward.shop.gear.pivot", gear_candidates, "pivot", picked, generation_index + 2)

    local offers = { heal }
    if support_gear then
        support_gear.name = support_gear.gearData.name
        support_gear.id = "gear_" .. support_gear.gearData.id
        support_gear.price = priceForOffer(support_gear)
        support_gear.sold = false
        offers[#offers + 1] = support_gear
    end

    if pivot_gear then
        pivot_gear.name = pivot_gear.gearData.name
        pivot_gear.id = "gear_" .. pivot_gear.gearData.id
        pivot_gear.price = priceForOffer(pivot_gear)
        pivot_gear.sold = false
        offers[#offers + 1] = pivot_gear
    else
        offers[#offers + 1] = ammo
    end

    local meta = context.run_metadata
    if meta then
        RunMetadata.recordShopGenerated(meta, offers, RunMetadata.snapshotBuild(player, profile), {
            difficulty = difficulty,
            source = context.source or "shop",
        })
    end

    return offers, profile
end

function RewardRuntime.reroll(surface, player, context)
    context = context or {}
    local normalized = normalizeSurface(surface)
    local run_meta = context.run_metadata
    local cost = RewardRuntime.getRerollCost(normalized, run_meta, context)
    if not player then
        return nil, cost, "Missing player"
    end
    local spent = player:spendGold(cost, normalized == "shop" and "shop_reroll" or "levelup_reroll")
    if not spent then
        return nil, cost, "Not enough gold"
    end

    local before_offers = context.current_offers or {}
    local offers, profile
    if normalized == "shop" then
        offers, profile = RewardRuntime.rollShopOffers(player, context)
    else
        offers, profile = RewardRuntime.rollLevelUpChoices(player, context)
    end

    if run_meta then
        RunMetadata.recordReroll(run_meta, normalized, cost, before_offers, offers, RunMetadata.snapshotBuild(player, profile))
    end
    return offers, cost, nil, profile
end

function RewardRuntime.recordChoice(run_meta, event)
    if not run_meta or type(event) ~= "table" then
        return
    end
    if event.kind == "levelup_choice" then
        RunMetadata.recordRewardChosen(run_meta, event.source or "levelup", event.chosen, event.offers, event.build_snapshot)
    elseif event.kind == "shop_purchase" then
        RunMetadata.recordShopPurchased(run_meta, event.item, event.build_snapshot, { price = event.price })
    end
end

return RewardRuntime
