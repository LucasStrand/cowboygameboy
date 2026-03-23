local MetaRuntime = {}
local Perks = require("src.data.perks")

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

-- Player-facing (HUD / recap); no raw packet_kind / family.
local function formatLastIncomingDamageLinePlayer(d)
    if not d then
        return nil
    end
    local label = d.source_name or d.enemy_type_id or d.source_id or "Unknown"
    local amt = tonumber(d.amount or 0) or 0
    return string.format("From %s · %d damage", tostring(label), amt)
end

-- Export, dev logs, causal toggle — full trace-style line.
local function formatLastIncomingDamageLineTechnical(d)
    if not d then
        return nil
    end
    local label = d.source_name or d.enemy_type_id or d.source_id or "unknown"
    return string.format(
        "%s  |  %s  |  %s  |  %d dmg",
        tostring(label),
        tostring(d.packet_kind or "?"),
        tostring(d.family or "?"),
        tonumber(d.amount or 0) or 0
    )
end

local function formatMajorProcLinePlayer(last_proc)
    if not last_proc or not last_proc.perk_id then
        return nil
    end
    local perk = Perks.getById(last_proc.perk_id)
    local name = perk and perk.name or last_proc.perk_id
    return string.format(
        "%s · %d damage",
        tostring(name),
        tonumber(last_proc.damage or 0) or 0
    )
end

local function formatMajorProcLineTechnical(last_proc)
    if not last_proc or not last_proc.perk_id then
        return nil
    end
    local perk = Perks.getById(last_proc.perk_id)
    local name = perk and perk.name or last_proc.perk_id
    return string.format(
        "%s — %s (%d)",
        tostring(name),
        tostring(last_proc.rule_id or "proc"),
        tonumber(last_proc.damage or 0) or 0
    )
end

local function cloneDamageBreakdown(breakdown)
    local out = {
        melee = 0,
        ultimate = 0,
        explosion = 0,
        proc = 0,
        physical = 0,
        magical = 0,
        true_damage = 0,
    }
    for key, value in pairs(breakdown or {}) do
        if type(value) == "number" then
            out[key] = value
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
            totalDamageDealt = 0,
            damageBreakdown = cloneDamageBreakdown(nil),
            dominantTags = {},
            latestBuild = nil,
            recentChoices = {},
            recentPurchases = {},
            lastDamageToPlayerLine = nil,
            lastDamageToPlayerLineTechnical = nil,
            lastMajorProcLine = nil,
            lastMajorProcLineTechnical = nil,
            lastDamageSourceType = nil,
            lastDamageSourceId = nil,
            lastDamageFamily = nil,
            lastDamagePacketKind = nil,
            lastMajorProcId = nil,
            visibleBuffCount = nil,
            recapOutcome = fallback.outcome,
            damageTracePrimarySource = nil,
            damageTraceLastEventSource = nil,
            damageTraceLastIncomingSource = nil,
        }
    end

    local latest = lastBuildSnapshot(run_meta)
    local run_end = run_meta.run_end or {}
    local milestones = run_meta.milestones or {}
    local checkpoints = milestones.checkpoints or {}
    local bosses = milestones.bosses or {}
    local combat = run_meta.combat or {}
    local dominant = dominantTagsFromSnapshots(run_meta)
    if #dominant == 0 and latest and latest.build_profile and latest.build_profile.dominant_tags then
        dominant = cloneList(latest.build_profile.dominant_tags)
    end

    local last_in = run_end.last_damage_to_player or combat.last_damage_to_player
    local last_proc = run_end.last_major_proc or combat.last_major_proc

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
        totalDamageDealt = (combat and combat.total_damage_dealt)
            or run_end.total_damage_dealt
            or 0,
        damageBreakdown = cloneDamageBreakdown((combat and combat.breakdown) or run_end.damage_breakdown),
        dominantTags = dominant,
        latestBuild = latest,
        recentChoices = recentChosenNames(run_meta),
        recentPurchases = recentNames(run_meta.shops and run_meta.shops.purchased or {}, "name", 3),
        rewardChoices = #(run_meta.rewards and run_meta.rewards.chosen or {}),
        shopPurchases = #(run_meta.shops and run_meta.shops.purchased or {}),
        lastDamageToPlayerLine = formatLastIncomingDamageLinePlayer(last_in),
        lastDamageToPlayerLineTechnical = formatLastIncomingDamageLineTechnical(last_in),
        lastMajorProcLine = formatMajorProcLinePlayer(last_proc),
        lastMajorProcLineTechnical = formatMajorProcLineTechnical(last_proc),
        lastDamageSourceType = last_in and last_in.source_type or nil,
        lastDamageSourceId = last_in and last_in.source_id or nil,
        lastDamageFamily = last_in and last_in.family or nil,
        lastDamagePacketKind = last_in and last_in.packet_kind or nil,
        lastMajorProcId = last_proc and last_proc.perk_id or nil,
        visibleBuffCount = run_end.visible_buff_count,
        recapOutcome = run_end.recap_outcome or run_end.outcome or fallback.outcome,
        damageTracePrimarySource = run_end.damage_trace_primary_source,
        damageTraceLastEventSource = run_end.damage_trace_last_event_source,
        damageTraceLastIncomingSource = run_end.damage_trace_last_incoming_source,
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
        string.format(
            "[meta] damage total=%d ult=%d explosion=%d proc=%d melee=%d",
            tonumber(summary.totalDamageDealt or 0) or 0,
            tonumber(summary.damageBreakdown and summary.damageBreakdown.ultimate or 0) or 0,
            tonumber(summary.damageBreakdown and summary.damageBreakdown.explosion or 0) or 0,
            tonumber(summary.damageBreakdown and summary.damageBreakdown.proc or 0) or 0,
            tonumber(summary.damageBreakdown and summary.damageBreakdown.melee or 0) or 0
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
    if summary.lastDamageToPlayerLineTechnical then
        lines[#lines + 1] = "[meta] last incoming: " .. tostring(summary.lastDamageToPlayerLineTechnical)
    elseif summary.lastDamageToPlayerLine then
        lines[#lines + 1] = "[meta] last incoming: " .. tostring(summary.lastDamageToPlayerLine)
    end
    if summary.lastMajorProcLineTechnical then
        lines[#lines + 1] = "[meta] major proc: " .. tostring(summary.lastMajorProcLineTechnical)
    elseif summary.lastMajorProcLine then
        lines[#lines + 1] = "[meta] major proc: " .. tostring(summary.lastMajorProcLine)
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
        string.format(
            "Damage: %d total  |  Ult %d  |  Expl %d  |  Proc %d",
            tonumber(summary.totalDamageDealt or 0) or 0,
            tonumber(summary.damageBreakdown and summary.damageBreakdown.ultimate or 0) or 0,
            tonumber(summary.damageBreakdown and summary.damageBreakdown.explosion or 0) or 0,
            tonumber(summary.damageBreakdown and summary.damageBreakdown.proc or 0) or 0
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
    if summary.lastDamageToPlayerLine then
        lines[#lines + 1] = "Last hit taken: " .. tostring(summary.lastDamageToPlayerLine)
    end
    if summary.lastMajorProcLine then
        lines[#lines + 1] = "Major proc: " .. tostring(summary.lastMajorProcLine)
    end
    return lines
end

return MetaRuntime
