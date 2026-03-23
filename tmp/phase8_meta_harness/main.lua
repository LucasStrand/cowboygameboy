local PROJECT_ROOT = [[C:\Users\9914k\Dev\Cowboygamejam\cowboygameboy]]
local OUTPUT_LOG = PROJECT_ROOT .. [[\tmp\phase8_meta_harness_output.txt]]

package.path = table.concat({
    PROJECT_ROOT .. [[\?.lua]],
    PROJECT_ROOT .. [[\?\init.lua]],
    package.path,
}, ";")

DEBUG = true
debugLog = function(_) end

package.loaded["src.systems.sfx"] = {
    play = function() end,
}

local CombatEvents
local DamagePacket
local DamageResolver
local GameRng
local Guns
local GearData
local MetaRuntime
local RewardRuntime
local RunMetadata
local Shop
local SourceRef

local lines = {}
local failures = {}

local function log(msg)
    lines[#lines + 1] = tostring(msg)
end

local function assertCase(name, condition, detail)
    if condition then
        log("[assert] PASS " .. name)
    else
        local message = "[assert] FAIL " .. name .. (detail and (" :: " .. detail) or "")
        log(message)
        failures[#failures + 1] = message
    end
end

local function containsText(haystack, needle)
    return type(haystack) == "string" and type(needle) == "string" and haystack:find(needle, 1, true) ~= nil
end

local function loadModule(name)
    local ok, value = pcall(require, name)
    if not ok then
        error(string.format("failed to require %s: %s", tostring(name), tostring(value)))
    end
    return value
end

local function setupRuntimeModules()
    CombatEvents = loadModule("src.systems.combat_events")
    DamagePacket = loadModule("src.systems.damage_packet")
    DamageResolver = loadModule("src.systems.damage_resolver")
    GameRng = loadModule("src.systems.game_rng")
    Guns = loadModule("src.data.guns")
    GearData = loadModule("src.data.gear")
    MetaRuntime = loadModule("src.systems.meta_runtime")
    RewardRuntime = loadModule("src.systems.reward_runtime")
    RunMetadata = loadModule("src.systems.run_metadata")
    Shop = loadModule("src.systems.shop")
    SourceRef = loadModule("src.systems.source_ref")
end

local function readGear(slot)
    for _, item in ipairs(GearData.pool) do
        if item.slot == slot then
            return item
        end
    end
    return nil
end

local function makePlayer(run_meta)
    local player = {
        actorId = "player",
        isPlayer = true,
        level = 7,
        gold = 220,
        hp = 100,
        runMetadata = run_meta,
        perks = {},
        gear = {
            hat = readGear("hat"),
            vest = readGear("vest"),
            boots = readGear("boots"),
            melee = nil,
            shield = nil,
        },
        weapons = {
            [1] = { gun = Guns.getById("revolver") },
            [2] = { gun = Guns.getById("ak47") },
        },
        stats = {
            cylinderSize = 6,
        },
        ammoAdded = 0,
    }

    function player:addGold(amount, reason)
        amount = math.floor(tonumber(amount) or 0)
        if amount <= 0 then
            return 0
        end
        self.gold = self.gold + amount
        if self.runMetadata then
            RunMetadata.recordEconomy(self.runMetadata, "earned", amount, reason or "gold_gain")
        end
        return amount
    end

    function player:spendGold(amount, reason)
        amount = math.max(0, math.floor(tonumber(amount) or 0))
        if amount <= 0 then
            return true, 0
        end
        if self.gold < amount then
            return false, amount
        end
        self.gold = self.gold - amount
        if self.runMetadata then
            RunMetadata.recordEconomy(self.runMetadata, "spent", amount, reason or "gold_spend")
        end
        return true, amount
    end

    function player:getEffectiveStats()
        local max_hp = 100
        for _, slot_name in ipairs({ "hat", "vest", "boots" }) do
            local gear = self.gear[slot_name]
            if gear and gear.stats and gear.stats.maxHP then
                max_hp = max_hp + gear.stats.maxHP
            end
        end
        return {
            maxHP = max_hp,
        }
    end

    function player:heal(amount)
        self.hp = math.min(self:getEffectiveStats().maxHP, self.hp + math.floor(tonumber(amount) or 0))
    end

    function player:equipGear(gear)
        if gear then
            self.gear[gear.slot] = gear
        end
    end

    function player:addAmmoToActiveSlot(amount)
        self.ammoAdded = self.ammoAdded + math.max(0, math.floor(tonumber(amount) or 0))
    end

    return player
end

local function makeBossEnemy()
    local enemy = {
        actorId = "boss_actor_01",
        typeId = "ogreboss",
        name = "Ogre Boss",
        cc_profile = "boss",
        isEnemy = true,
        alive = true,
        hp = 40,
        armor = 0,
        x = 120,
        y = 40,
        w = 32,
        h = 32,
    }

    function enemy:applyResolvedDamage(result, _, packet)
        self.lastPacket = packet
        self.hp = self.hp - (result.final_damage or 0)
        if self.hp <= 0 then
            self.alive = false
            self.isEnemy = false
        end
        return true, result.final_damage or 0, self.hp <= 0
    end

    return enemy
end

local function recordBossKillFromPayload(run_meta, payload, room_ctx)
    if not payload or payload.target_kind ~= "enemy" then
        return
    end
    local target = payload.target_actor
    if not target or target.cc_profile ~= "boss" then
        return
    end
    RunMetadata.recordBossKilled(run_meta, target, {
        room_id = room_ctx.room_id,
        room_name = room_ctx.room_name,
        world_id = room_ctx.world_id,
        world_name = room_ctx.world_name,
        room_index = room_ctx.room_index,
        total_cleared = room_ctx.total_cleared,
        difficulty = room_ctx.difficulty,
        dev_arena = room_ctx.dev_arena,
    })
end

local function deterministicSummaryString(summary)
    return table.concat({
        tostring(summary.outcome),
        tostring(summary.roomsCleared),
        tostring(summary.checkpointsReached),
        tostring(summary.bossesKilled),
        tostring(summary.perksPicked),
        tostring(summary.goldEarned),
        tostring(summary.goldSpent),
        tostring(summary.rerollsUsed),
        table.concat(summary.dominantTags or {}, ","),
        table.concat(summary.recentChoices or {}, ","),
        table.concat(summary.recentPurchases or {}, ","),
    }, "|")
end

function love.load()
    local ok, err = xpcall(function()
        setupRuntimeModules()
        CombatEvents.clear()
        GameRng.setCurrent(GameRng.new(80808))

        local run_meta = RunMetadata.new(80808, {
            world_id = "desert",
            world_name = "Desert Frontier",
            dev_arena = false,
        })
        local player = makePlayer(run_meta)

        player:addGold(90, "combat_gold")
        RunMetadata.recordRoom(run_meta, {
            id = "desert_room_01",
            name = "Dusty Approach",
            bossFight = false,
        }, {
            world_id = "desert",
            room_index = 1,
            total_cleared = 0,
            difficulty = 1,
            dev_arena = false,
        })

        local offers1, profile1 = RewardRuntime.rollLevelUpChoices(player, {
            run_metadata = run_meta,
            source = "levelup",
        })
        local chosen1 = offers1[1]
        player.perks[#player.perks + 1] = chosen1.id
        RewardRuntime.recordChoice(run_meta, {
            kind = "levelup_choice",
            source = "levelup",
            chosen = chosen1,
            offers = offers1,
            build_snapshot = RunMetadata.snapshotBuild(player, RewardRuntime.buildProfile(player, {
                source = "levelup_choice",
            })),
        })

        local rerolled_offers, reroll_cost = RewardRuntime.reroll("levelup", player, {
            run_metadata = run_meta,
            source = "levelup",
            current_offers = offers1,
        })
        assertCase("levelup reroll succeeded", rerolled_offers ~= nil, tostring(reroll_cost))
        local chosen2 = rerolled_offers[2] or rerolled_offers[1]
        player.perks[#player.perks + 1] = chosen2.id
        RewardRuntime.recordChoice(run_meta, {
            kind = "levelup_choice",
            source = "levelup",
            chosen = chosen2,
            offers = rerolled_offers,
            build_snapshot = RunMetadata.snapshotBuild(player, RewardRuntime.buildProfile(player, {
                source = "levelup_choice_rerolled",
            })),
        })

        RunMetadata.recordShopVisit(run_meta, {
            source = "saloon_shop_enter",
            difficulty = 2,
            gold_before = player.gold,
        })
        local shop = Shop.new(2, player, {
            run_metadata = run_meta,
            source = "saloon_shop",
        })
        assertCase("shop generated offers", #shop.items > 0, tostring(#shop.items))
        local bought_index = 1
        local buy_ok, buy_msg = shop:buyItem(bought_index, player)
        assertCase("shop buy succeeded", buy_ok == true, tostring(buy_msg))
        local shop_reroll_ok, _, shop_reroll_cost = shop:reroll(player)
        assertCase("shop reroll succeeded", shop_reroll_ok == true, tostring(shop_reroll_cost))
        RunMetadata.recordShopVisit(run_meta, {
            source = "saloon_shop_leave",
            difficulty = 2,
            gold_after = player.gold,
        })

        RunMetadata.recordRoom(run_meta, {
            id = "desert_room_05_boss",
            name = "Ogre Showdown",
            bossFight = true,
        }, {
            world_id = "desert",
            room_index = 5,
            total_cleared = 4,
            difficulty = 2,
            dev_arena = false,
        })
        RunMetadata.recordCheckpoint(run_meta, {
            world_id = "desert",
            world_name = "Desert Frontier",
            room_index = 5,
            total_cleared = 5,
            difficulty = 2,
            dev_arena = false,
        })

        local room_ctx = {
            room_id = "desert_room_05_boss",
            room_name = "Ogre Showdown",
            world_id = "desert",
            world_name = "Desert Frontier",
            room_index = 5,
            total_cleared = 5,
            difficulty = 2,
            dev_arena = false,
        }

        local boss_enemy = makeBossEnemy()
        local grunt_enemy = {
            actorId = "grunt_01",
            typeId = "bandit",
            name = "Bandit",
            cc_profile = "normal",
            isEnemy = true,
            alive = true,
            hp = 20,
            armor = 0,
            x = 60,
            y = 40,
            w = 20,
            h = 20,
            applyResolvedDamage = function(self, result)
                self.hp = self.hp - (result.final_damage or 0)
                if self.hp <= 0 then
                    self.alive = false
                    self.isEnemy = false
                end
                return true, result.final_damage or 0, self.hp <= 0
            end,
        }

        CombatEvents.subscribe("OnKill", function(payload)
            recordBossKillFromPayload(run_meta, payload, room_ctx)
        end)

        local function killTarget(target, damage_amount, source_id)
            return DamageResolver.resolve_packet({
                packet = DamagePacket.new({
                    kind = "direct_hit",
                    family = "physical",
                    base_min = damage_amount,
                    base_max = damage_amount,
                    source = SourceRef.new({
                        owner_actor_id = player.actorId,
                        owner_source_type = "weapon_slot",
                        owner_source_id = source_id,
                    }),
                    target_id = target.actorId,
                    snapshot_data = {
                        source_context = {
                            base_min = damage_amount,
                            base_max = damage_amount,
                            damage = 1,
                            physical_damage = 0,
                            magical_damage = 0,
                            true_damage = 0,
                            crit_chance = 0,
                            crit_damage = 1.5,
                            armor_pen = 0,
                            magic_pen = 0,
                        },
                    },
                }),
                source_actor = player,
                target_actor = target,
                target_kind = "enemy",
            })
        end

        killTarget(grunt_enemy, 50, "revolver")
        assertCase(
            "normal enemy kill does not increment boss count",
            (run_meta.milestones and run_meta.milestones.bosses and run_meta.milestones.bosses.kills or 0) == 0
        )

        killTarget(boss_enemy, 50, "revolver")
        assertCase(
            "boss kill increments boss count once",
            (run_meta.milestones and run_meta.milestones.bosses and run_meta.milestones.bosses.kills or 0) == 1
        )

        local end_profile = RewardRuntime.buildProfile(player, {
            source = "truth_gate_end",
        })
        RunMetadata.finishRun(run_meta, {
            outcome = "death",
            source = "truth_gate_end",
            level = player.level,
            rooms_cleared = 5,
            gold = player.gold,
            perks_count = #player.perks,
            dominant_tags = end_profile.dominant_tags,
            build_snapshot = RunMetadata.snapshotBuild(player, end_profile),
        })

        local summary = MetaRuntime.summarize(run_meta, {
            roomsCleared = 5,
            perksCount = #player.perks,
            outcome = "death",
        })
        local summary_again = MetaRuntime.summarize(run_meta, {
            roomsCleared = 5,
            perksCount = #player.perks,
            outcome = "death",
        })
        local recap_lines = MetaRuntime.toRecapLines(summary)
        local debug_lines = MetaRuntime.toDebugLines(summary)

        assertCase("summary gold earned matches canonical economy", summary.goldEarned == run_meta.economy.gold_earned, tostring(summary.goldEarned))
        assertCase("summary gold spent matches canonical economy", summary.goldSpent == run_meta.economy.gold_spent, tostring(summary.goldSpent))
        assertCase(
            "summary rerolls match canonical economy counts",
            summary.rerollsUsed == ((run_meta.economy.reroll_counts.levelup or 0) + (run_meta.economy.reroll_counts.shop or 0)),
            tostring(summary.rerollsUsed)
        )
        assertCase("summary perks picked matches reward history", summary.perksPicked == #run_meta.rewards.chosen, tostring(summary.perksPicked))
        assertCase("summary checkpoints match milestone history", summary.checkpointsReached == run_meta.milestones.checkpoints.count, tostring(summary.checkpointsReached))
        assertCase("summary bosses match actual boss kill history", summary.bossesKilled == run_meta.milestones.bosses.kills, tostring(summary.bossesKilled))
        assertCase("summary is deterministic for same metadata snapshot", deterministicSummaryString(summary) == deterministicSummaryString(summary_again))
        assertCase("debug dump includes boss count", containsText(debug_lines[1], "bosses=1"), tostring(debug_lines[1]))
        assertCase("recap lines include checkpoint count", containsText(recap_lines[3], "Checkpoints 1"), tostring(recap_lines[3]))
        assertCase("recap lines include boss kill count", containsText(recap_lines[3], "Bosses 1"), tostring(recap_lines[3]))
        assertCase("recap lines include recent picks", #recap_lines >= 4 and containsText(table.concat(recap_lines, " | "), "Recent picks:"), table.concat(recap_lines, " | "))
        assertCase("recent shop purchase is present in summary", #summary.recentPurchases >= 1, table.concat(summary.recentPurchases or {}, ","))

        local gold_spent_before_recap = summary.goldSpent
        local rerolls_before_recap = summary.rerollsUsed
        RunMetadata.finishRun(run_meta, {
            outcome = "recap",
            source = "dev_recap",
            level = player.level,
            rooms_cleared = 5,
            gold = player.gold,
            perks_count = #player.perks,
            dominant_tags = end_profile.dominant_tags,
            build_snapshot = RunMetadata.snapshotBuild(player, end_profile),
        })
        local after_recap_summary = MetaRuntime.summarize(run_meta, {
            roomsCleared = 5,
            perksCount = #player.perks,
            outcome = "recap",
        })
        assertCase("opening recap does not mutate gold totals", after_recap_summary.goldSpent == gold_spent_before_recap, tostring(after_recap_summary.goldSpent))
        assertCase("opening recap does not mutate reroll totals", after_recap_summary.rerollsUsed == rerolls_before_recap, tostring(after_recap_summary.rerollsUsed))

        log("summary outcome=" .. tostring(summary.outcome))
        log("summary rooms=" .. tostring(summary.roomsCleared))
        log("summary checkpoints=" .. tostring(summary.checkpointsReached))
        log("summary bosses=" .. tostring(summary.bossesKilled))
        log("summary perks=" .. tostring(summary.perksPicked))
        log("summary gold_earned=" .. tostring(summary.goldEarned))
        log("summary gold_spent=" .. tostring(summary.goldSpent))
        log("summary rerolls=" .. tostring(summary.rerollsUsed))
        log("summary dominant_tags=" .. table.concat(summary.dominantTags or {}, ", "))
        for _, line in ipairs(debug_lines) do
            log("[debug_line] " .. line)
        end
        for _, line in ipairs(recap_lines) do
            log("[recap_line] " .. line)
        end
    end, debug.traceback)

    if not ok then
        log("[fatal] " .. tostring(err))
        failures[#failures + 1] = tostring(err)
    end

    local fh = assert(io.open(OUTPUT_LOG, "w"))
    for _, line in ipairs(lines) do
        fh:write(line, "\n")
    end
    fh:write("SUMMARY: " .. (#failures == 0 and "PASS" or ("FAIL (" .. tostring(#failures) .. ")")) .. "\n")
    fh:close()

    love.event.quit(#failures == 0 and 0 or 1)
end
