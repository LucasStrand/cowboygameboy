local MetaRuntime = {}

-- Raw run metadata is the canonical source of truth.
-- This module only derives read-only summaries and presentation text.

local function cloneList(list)
    local out = {}
    for i, value in ipairs(list or {}) do
        out[i] = value
    end
    return out
end

local function sortedTags(weights, max_count)
    local items = {}
    for tag, weight in pairs(weights or {}) do
        if type(weight) == "number" and weight > 0 then
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
    for i = 1, math.min(max_count or 4, #items) do
        out[#out + 1] = items[i].tag
    end
    return out
end

local function lastBuildSnapshot(run_meta)
    local snapshots = run_meta and run_meta.build_snapshots or nil
    if not snapshots or #snapshots == 0 then
        return nil
    end
    return snapshots[#snapshots]
end

local function dominantTagsFromSnapshots(run_meta)
    local weights = {}
    for _, snapshot in ipairs(run_meta and run_meta.build_snapshots or {}) do
        local tags = snapshot and snapshot.build_profile and snapshot.build_profile.dominant_tags or {}
        for index, tag in ipairs(tags) do
            weights[tag] = (weights[tag] or 0) + math.max(1, 5 - index)
        end
    end
    return sortedTags(weights, 4)
end

local function recentNames(entries, key, max_count)
    local out = {}
    for i = #entries, 1, -1 do
        local name = entries[i] and entries[i][key] or nil
        if type(name) == "string" and name ~= "" then
            out[#out + 1] = name
            if #out >= (max_count or 3) then
                break
            end
        end
    end
    return out
end

local function recentChosenNames(run_meta)
    local out = {}
    local entries = run_meta and run_meta.rewards and run_meta.rewards.chosen or {}
    for i = #entries, 1, -1 do
        local chosen = entries[i] and entries[i].chosen or nil
        local name = chosen and (chosen.name or chosen.id) or nil
        if type(name) == "string" and name ~= "" then
            out[#out + 1] = name
            if #out >= 3 then
                break
            end
        end
    end
    return out
end

function MetaRuntime.summarize(run_meta, fallback)
    fallback = fallback or {}
    if not run_meta then
        return {
            outcome = fallback.outcome,
            roomsCleared = fallback.roomsCleared or 0,
            checkpointsReached = 0,
            bossesKilled = 0,
            perksPicked = fallback.perksCount or 0,
            goldEarned = 0,
            goldSpent = 0,
            rerollsUsed = 0,
            dominantTags = {},
            recentChoices = {},
            recentPurchases = {},
        }
    end

    local latest = lastBuildSnapshot(run_meta)
    local run_end = run_meta.run_end or {}
    local milestones = run_meta.milestones or {}
    local checkpoints = milestones.checkpoints or {}
    local bosses = milestones.bosses or {}
    local dominant = dominantTagsFromSnapshots(run_meta)
    if #dominant == 0 and latest and latest.build_profile and latest.build_profile.dominant_tags then
        dominant = cloneList(latest.build_profile.dominant_tags)
    end

    return {
        outcome = run_end.outcome or fallback.outcome,
        seed = run_meta.seed,
        worldName = run_meta.route and run_meta.route.world_name or fallback.worldName,
        worldId = run_meta.route and run_meta.route.world_id or nil,
        roomsCleared = run_end.rooms_cleared or fallback.roomsCleared
            or (run_meta.rooms[#run_meta.rooms] and run_meta.rooms[#run_meta.rooms].total_cleared) or 0,
        checkpointsReached = checkpoints.count or #(checkpoints.history or {}),
        bossesKilled = bosses.kills or #(bosses.history or {}),
        perksPicked = #(run_meta.rewards and run_meta.rewards.chosen or {}),
        goldEarned = run_meta.economy and run_meta.economy.gold_earned or 0,
        goldSpent = run_meta.economy and run_meta.economy.gold_spent or 0,
        rerollsUsed = (run_meta.economy and run_meta.economy.reroll_counts
            and ((run_meta.economy.reroll_counts.levelup or 0) + (run_meta.economy.reroll_counts.shop or 0))) or 0,
        dominantTags = dominant,
        latestBuild = latest,
        recentChoices = recentChosenNames(run_meta),
        recentPurchases = recentNames(run_meta.shops and run_meta.shops.purchased or {}, "name", 3),
        rewardChoices = #(run_meta.rewards and run_meta.rewards.chosen or {}),
        shopPurchases = #(run_meta.shops and run_meta.shops.purchased or {}),
    }
end

function MetaRuntime.toDebugLines(summary)
    summary = summary or {}
    local lines = {
        string.format(
            "[meta] rooms=%d checkpoints=%d bosses=%d perks=%d rerolls=%d",
            tonumber(summary.roomsCleared or 0) or 0,
            tonumber(summary.checkpointsReached or 0) or 0,
            tonumber(summary.bossesKilled or 0) or 0,
            tonumber(summary.perksPicked or 0) or 0,
            tonumber(summary.rerollsUsed or 0) or 0
        ),
        string.format(
            "[meta] gold earned=$%d spent=$%d choices=%d purchases=%d",
            tonumber(summary.goldEarned or 0) or 0,
            tonumber(summary.goldSpent or 0) or 0,
            tonumber(summary.rewardChoices or 0) or 0,
            tonumber(summary.shopPurchases or 0) or 0
        ),
    }
    if summary.seed or summary.worldName then
        lines[#lines + 1] = string.format(
            "[meta] route=%s seed=%s outcome=%s",
            tostring(summary.worldName or summary.worldId or "unknown"),
            tostring(summary.seed or "n/a"),
            tostring(summary.outcome or "unknown")
        )
    end
    if summary.dominantTags and #summary.dominantTags > 0 then
        lines[#lines + 1] = "[meta] dominant tags: " .. table.concat(summary.dominantTags, ", ")
    end
    if summary.recentChoices and #summary.recentChoices > 0 then
        lines[#lines + 1] = "[meta] recent picks: " .. table.concat(summary.recentChoices, ", ")
    end
    if summary.recentPurchases and #summary.recentPurchases > 0 then
        lines[#lines + 1] = "[meta] recent buys: " .. table.concat(summary.recentPurchases, ", ")
    end
    return lines
end

function MetaRuntime.toRecapLines(summary)
    summary = summary or {}
    local lines = {
        string.format(
            "Route: %s  |  Seed: %s  |  Outcome: %s",
            tostring(summary.worldName or summary.worldId or "unknown"),
            tostring(summary.seed or "n/a"),
            tostring(summary.outcome or "unknown")
        ),
        string.format(
            "Economy: +$%d  |  -$%d  |  Rerolls %d",
            tonumber(summary.goldEarned or 0) or 0,
            tonumber(summary.goldSpent or 0) or 0,
            tonumber(summary.rerollsUsed or 0) or 0
        ),
        string.format(
            "Milestones: Checkpoints %d  |  Bosses %d  |  Picks %d",
            tonumber(summary.checkpointsReached or 0) or 0,
            tonumber(summary.bossesKilled or 0) or 0,
            tonumber(summary.perksPicked or 0) or 0
        ),
    }
    if summary.dominantTags and #summary.dominantTags > 0 then
        lines[#lines + 1] = "Build: " .. table.concat(summary.dominantTags, ", ")
    end
    if summary.recentChoices and #summary.recentChoices > 0 then
        lines[#lines + 1] = "Recent picks: " .. table.concat(summary.recentChoices, ", ")
    end
    if summary.recentPurchases and #summary.recentPurchases > 0 then
        lines[#lines + 1] = "Recent buys: " .. table.concat(summary.recentPurchases, ", ")
    end
    return lines
end

return MetaRuntime
