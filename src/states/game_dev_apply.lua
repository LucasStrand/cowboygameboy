-- Dev panel actions (extracted from game.lua to stay under LuaJIT's 60-upvalue limit per function).
local Gamestate = require("lib.hump.gamestate")
local Progression = require("src.systems.progression")
local Buffs = require("src.systems.buffs")
local SourceRef = require("src.systems.source_ref")
local DevLog = require("src.ui.devlog")
local ContentTooltips = require("src.systems.content_tooltips")
local RewardRuntime = require("src.systems.reward_runtime")
local RunMetadata = require("src.systems.run_metadata")
local MetaRuntime = require("src.systems.meta_runtime")
local Phase10Telemetry = require("src.systems.phase10_telemetry")

local function adminToolsEnabled()
    return DEBUG or DEV_TOOLS_ENABLED
end

local function devPerkById(pid)
    local Perks = require("src.data.perks")
    for _, p in ipairs(Perks.pool) do
        if p.id == pid then return p end
    end
end

local function devPlayerHasPerk(player, pid)
    if not player then return true end
    for _, id in ipairs(player.perks) do
        if id == pid then return true end
    end
    return false
end

local function ensurePerk(player, pid)
    if devPlayerHasPerk(player, pid) then
        return false
    end
    local perk = devPerkById(pid)
    if perk then
        Progression.applyPerk(player, perk)
        return true
    end
    return false
end

local function nearestLivingEnemy(player, enemies)
    if not player or not enemies then
        return nil
    end

    local px = player.x + player.w * 0.5
    local py = player.y + player.h * 0.5
    local bestEnemy = nil
    local bestDistSq = math.huge

    for _, enemy in ipairs(enemies) do
        if enemy and enemy.alive then
            local ex = enemy.x + enemy.w * 0.5
            local ey = enemy.y + enemy.h * 0.5
            local dx = ex - px
            local dy = ey - py
            local distSq = dx * dx + dy * dy
            if distSq < bestDistSq then
                bestDistSq = distSq
                bestEnemy = enemy
            end
        end
    end

    return bestEnemy
end

local function statusDuration(status_id)
    local def = Buffs.getDef(status_id)
    if not def then
        return nil
    end
    return def.duration or def.base_duration
end

local function getNumericStat(stats, ...)
    if type(stats) ~= "table" then
        return 0
    end
    local keys = { ... }
    for _, key in ipairs(keys) do
        local value = stats[key]
        if type(value) == "number" then
            return value
        end
    end
    return 0
end

local function inferredHitBase(player, family)
    local stats = player and player:getEffectiveStats() or {}
    local generic = getNumericStat(stats, "damage")
    local physical = getNumericStat(stats, "physicalDamage", "physical_damage")
    local magical = getNumericStat(stats, "magicalDamage", "magical_damage")

    if family == "physical" then
        return math.max(6, math.floor(generic + physical + 0.5))
    elseif family == "magical" then
        return math.max(6, math.floor(generic + magical + 0.5))
    end

    return math.max(6, math.floor(generic + 0.5))
end

local function snapshotSourceContext(family)
    return {
        damage = 1,
        physical_damage = 0,
        magical_damage = 0,
        true_damage = 0,
        crit_chance = 0,
        crit_damage = 1.5,
        armor_pen = 0,
        magic_pen = 0,
    }
end

local function buildStatusApplicationSpec(player, target_actor, target_kind, status_id, world)
    local source = SourceRef.new({
        owner_actor_id = player and player.actorId or "debug_actor",
        owner_source_type = "debug_tool",
        owner_source_id = "status_lab:" .. tostring(status_id),
    })
    local spec = {
        id = status_id,
        stacks = 1,
        duration = statusDuration(status_id),
        source = source,
        source_actor = player,
        target_actor = target_actor,
        runtime_ctx = {
            owner_actor = target_actor,
            target_kind = target_kind,
            world = world,
            source_actor = player,
        },
        metadata = {
            debug_harness = true,
            source = "status_lab",
        },
    }

    if status_id == "bleed" then
        local base_hit = inferredHitBase(player, "physical")
        spec.snapshot_data = {
            tick_damage = math.max(1, math.floor(base_hit * 0.18)),
            tick_damage_per_stack = true,
            family = "physical",
            source_context = snapshotSourceContext("physical"),
        }
    elseif status_id == "burn" then
        local source_level = player and player.level or 1
        spec.snapshot_data = {
            tick_damage = math.max(1, math.floor(2 * (1 + 0.10 * math.max(0, source_level - 1)))),
            tick_damage_per_stack = true,
            family = "magical",
            source_context = snapshotSourceContext("magical"),
        }
    elseif status_id == "shock" then
        local base_hit = inferredHitBase(player, "magical")
        spec.snapshot_data = {
            overload_damage = math.max(1, math.floor(base_hit * 0.75)),
            overload_stun_duration = 0.6,
            source_context = snapshotSourceContext("magical"),
        }
    end

    return spec
end

local function logStatusTracker(label, tracker)
    if not tracker then
        DevLog.push("sys", "[dev] " .. label .. ": no tracker")
        return
    end

    local top = Buffs.getTopStatuses(tracker, 8)
    local control = Buffs.getControlState(tracker)
    local cc = tracker.cc_state or {}
    local mods = Buffs.getStatMods(tracker)
    local count = 0
    for _ in pairs(tracker.instances or {}) do
        count = count + 1
    end

    DevLog.push("sys", string.format(
        "[dev] %s status dump: count=%d stunned=%s hard_cc_count=%s immunity=%.2f",
        label,
        count,
        tostring(control.stunned),
        tostring(cc.hard_cc_count or 0),
        cc.hard_cc_immunity_timer or 0
    ))

    if next(mods) then
        local mod_parts = {}
        for stat, value in pairs(mods) do
            mod_parts[#mod_parts + 1] = string.format("%s=%s", tostring(stat), tostring(value))
        end
        table.sort(mod_parts)
        DevLog.push("sys", "[dev] " .. label .. " stat mods: " .. table.concat(mod_parts, ", "))
    end

    if #top == 0 then
        DevLog.push("sys", "[dev] " .. label .. " statuses: none")
        return
    end

    for _, entry in ipairs(top) do
        DevLog.push("sys", string.format(
            "[dev] %s status: %s stacks=%s remaining=%.2f category=%s",
            label,
            tostring(entry.id),
            tostring(entry.stacks or 1),
            tonumber(entry.remaining_duration) or 0,
            tostring(entry.category)
        ))
    end
end

local function applyDebugStatus(player, target_actor, target_kind, status_id, world)
    if not target_actor or not target_actor.statuses then
        return false
    end
    local ok = Buffs.applyStatus(target_actor.statuses, buildStatusApplicationSpec(player, target_actor, target_kind, status_id, world))
    return ok == true
end

local function advanceStatusTime(player, target_actor, target_kind, world, seconds)
    if not target_actor or not target_actor.statuses then
        return false
    end
    local remaining = math.max(0, tonumber(seconds) or 0)
    while remaining > 0 do
        local step = math.min(0.25, remaining)
        Buffs.update(target_actor.statuses, step, {
            owner_actor = target_actor,
            target_kind = target_kind,
            world = world,
            source_actor = player,
        })
        remaining = remaining - step
    end
    return true
end

local function ensureDevShop(ctx)
    local Shop = require("src.systems.shop")
    ctx.devRewardLab = ctx.devRewardLab or {}
    if not ctx.devRewardLab.shop then
        ctx.devRewardLab.shop = Shop.new((ctx.roomManager and ctx.roomManager.difficulty) or 1, ctx.player, {
            run_metadata = ctx.player and ctx.player.runMetadata or nil,
            source = "dev_arena_shop",
            room_manager = ctx.roomManager,
        })
    end
    return ctx.devRewardLab.shop
end

local function rebuildDevShopDescriptions(shop)
    for _, item in ipairs((shop and shop.items) or {}) do
        if item.type == "gear" and item.gearData then
            item.description = ContentTooltips.getJoinedText("gear", item.gearData)
        elseif item.tooltip_key or item.tooltip_override then
            item.description = ContentTooltips.getJoinedText("offer", item)
        end
    end
end

local function logRewardProfile(player, source)
    local profile = RewardRuntime.buildProfile(player, { source = source or "dev_reward_lab" })
    DevLog.push("sys", "[reward] profile: " .. RewardRuntime.describeProfile(profile))
    return profile
end

--- ctx is game._runtime filled by game.lua before each call.
local function apply(id, ctx)
    if not adminToolsEnabled() or not ctx.player or not id then return end
    local player = ctx.player
    local devPanelState = ctx.devPanelState
    local devRebuildPanelRows = ctx.devRebuildPanelRows
    local devClampScroll = ctx.devClampScroll
    local devNpcSpawn = ctx.devNpcSpawn
    local getMouseWorldPosition = ctx.getMouseWorldPosition
    local updateDevSpawnPreview = ctx.updateDevSpawnPreview
    local currentDevSpawnCount = ctx.currentDevSpawnCount
    local clearDevNpcPlacement = ctx.clearDevNpcPlacement
    local world = ctx.world
    local enemies = ctx.enemies
    local pendingEnemiesIncoming = ctx.pendingEnemiesIncoming
    local currentRoom = ctx.currentRoom
    local bullets = ctx.bullets
    local startDevNpcPlacement = ctx.startDevNpcPlacement
    local roomManager = ctx.roomManager
    local syncCurrentRoomNightMode = ctx.syncCurrentRoomNightMode
    local spawnCheatGoldDrops = ctx.spawnCheatGoldDrops
    local gameRef = ctx.gameRef
    local devRewardLab = ctx.devRewardLab
    local queueRunRecap = ctx.queueRunRecap
    local nearestEnemy = nearestLivingEnemy(player, enemies)

    if id:sub(1, 8) == "section:" then
        local sectionId = id:sub(9)
        devPanelState.sections = devPanelState.sections or {}
        devPanelState.sections[sectionId] = not (devPanelState.sections[sectionId] == true)
        devRebuildPanelRows()
        devClampScroll()
        return
    elseif id == "npc_toggle_peaceful" then
        devNpcSpawn.peaceful = not devNpcSpawn.peaceful
        devRebuildPanelRows()
        devClampScroll()
        DevLog.push("sys", "[dev] NPC peaceful " .. (devNpcSpawn.peaceful and "on" or "off"))
        return
    elseif id == "npc_toggle_unarmed" then
        devNpcSpawn.unarmed = not devNpcSpawn.unarmed
        devRebuildPanelRows()
        devClampScroll()
        DevLog.push("sys", "[dev] NPC unarmed " .. (devNpcSpawn.unarmed and "on" or "off"))
        return
    elseif id == "npc_count_1" or id == "npc_count_5" or id == "npc_count_10" then
        devNpcSpawn.countIndex = (id == "npc_count_1" and 1) or (id == "npc_count_5" and 2) or 3
        if devNpcSpawn.placement then
            local wx, wy = getMouseWorldPosition()
            updateDevSpawnPreview(wx, wy)
        end
        devRebuildPanelRows()
        devClampScroll()
        DevLog.push("sys", "[dev] NPC count " .. tostring(currentDevSpawnCount()) .. "x")
        return
    elseif id == "npc_cancel_placement" then
        clearDevNpcPlacement(true)
        devRebuildPanelRows()
        devClampScroll()
        return
    elseif id == "kill_player" then
        devPanelState.open = false
        ctx.characterSheetOpen = false
        clearDevNpcPlacement(false)
        player:beginDeath()
        DevLog.push("sys", "[dev] kill player")
    elseif id == "full_heal" then
        player.hp = player:getEffectiveStats().maxHP
        DevLog.push("sys", "[dev] full heal")
    elseif id == "hurt_1" then
        if not player.devGodMode then
            player.hp = math.max(1, player.hp - 1)
        end
        DevLog.push("sys", "[dev] hurt 1")
    elseif id == "toggle_hitboxes" then
        ctx.devShowHitboxes = not ctx.devShowHitboxes
        devRebuildPanelRows()
        devClampScroll()
        DevLog.push("sys", "[dev] hitboxes " .. (ctx.devShowHitboxes and "on" or "off"))
    elseif id == "toggle_dev_pause" then
        devPanelState.pauseGameplay = not (devPanelState.pauseGameplay ~= false)
        devRebuildPanelRows()
        devClampScroll()
        DevLog.push("sys", "[dev] gameplay " .. ((devPanelState.pauseGameplay ~= false) and "paused" or "live"))
    elseif id == "time_auto" then
        roomManager.nightVisualsOverride = nil
        syncCurrentRoomNightMode()
        devRebuildPanelRows()
        devClampScroll()
        DevLog.push("sys", "[dev] time sim: auto (room data)")
    elseif id == "time_day" then
        roomManager.nightVisualsOverride = false
        syncCurrentRoomNightMode()
        devRebuildPanelRows()
        devClampScroll()
        DevLog.push("sys", "[dev] time sim: force day")
    elseif id == "time_night" then
        roomManager.nightVisualsOverride = true
        syncCurrentRoomNightMode()
        devRebuildPanelRows()
        devClampScroll()
        DevLog.push("sys", "[dev] time sim: force night")
    elseif id == "toggle_god" then
        player.devGodMode = not player.devGodMode
        DevLog.push("sys", "[dev] god mode " .. tostring(player.devGodMode))
    elseif id == "ult_full" then
        player.ultCharge = 1
        DevLog.push("sys", "[dev] ult charge full")
    elseif id == "gold_100" then
        spawnCheatGoldDrops(100)
        DevLog.push("sys", "[dev] +100 gold (drops)")
    elseif id == "gold_500" then
        spawnCheatGoldDrops(500)
        DevLog.push("sys", "[dev] +500 gold (drops)")
    elseif id == "xp_50" then
        devPanelState.open = false
        ctx.characterSheetOpen = false
        clearDevNpcPlacement(false)
        if player:addXP(50) then
            local levelup = require("src.states.levelup")
            Gamestate.push(levelup, player, function() end)
        end
    elseif id == "xp_200" then
        devPanelState.open = false
        ctx.characterSheetOpen = false
        clearDevNpcPlacement(false)
        if player:addXP(200) then
            local levelup = require("src.states.levelup")
            Gamestate.push(levelup, player, function() end)
        end
    elseif id == "preset_phase6_revolver_explosive" or id == "preset_phase6_ak_explosive"
        or id == "preset_phase6_blunderbuss_explosive" or id == "preset_phase6_proc_revolver" then
        local Guns = require("src.data.guns")
        local gunId = (id == "preset_phase6_revolver_explosive" and "revolver")
            or (id == "preset_phase6_ak_explosive" and "ak47")
            or (id == "preset_phase6_blunderbuss_explosive" and "blunderbuss")
            or "revolver"
        local gunDef = Guns.getById(gunId)
        if gunDef then
            player:equipWeapon(gunDef, player.activeWeaponSlot)
        end
        if id == "preset_phase6_proc_revolver" then
            ensurePerk(player, "phantom_third")
            DevLog.push("sys", "[dev] preset: phase6 proc revolver")
        else
            ensurePerk(player, "explosive_rounds")
            DevLog.push("sys", "[dev] preset: " .. gunId .. " + explosive rounds")
        end
        player.hp = player:getEffectiveStats().maxHP
        player.ultCharge = 1
        devRebuildPanelRows()
        devClampScroll()
    elseif id == "preset_phase10_proc_explosion_stress" then
        local Guns = require("src.data.guns")
        local gunDef = Guns.getById("blunderbuss")
        if gunDef then
            player:equipWeapon(gunDef, player.activeWeaponSlot)
        end
        ensurePerk(player, "phantom_third")
        ensurePerk(player, "explosive_rounds")
        player.ultCharge = 1
        player.hp = player:getEffectiveStats().maxHP
        devRebuildPanelRows()
        devClampScroll()
        if love and love.timer then
            ctx.phase10StressWallStart = love.timer.getTime()
        end
        DevLog.push("sys", "[dev] preset: Phase 10 proc + explosive stress (blunderbuss) [stress wall timer started]")
    elseif id == "preset_phase9_clutter_readability" then
        local Guns = require("src.data.guns")
        local gunDef = Guns.getById("revolver")
        if gunDef then
            player:equipWeapon(gunDef, player.activeWeaponSlot)
        end
        ensurePerk(player, "phantom_third")
        ensurePerk(player, "explosive_rounds")
        player.ultCharge = 1
        player.hp = math.max(1, math.floor(player:getEffectiveStats().maxHP * 0.5))
        applyDebugStatus(player, player, "player", "burn", world)
        applyDebugStatus(player, player, "player", "shock", world)
        applyDebugStatus(player, player, "player", "bleed", world)
        devRebuildPanelRows()
        devClampScroll()
        DevLog.push("sys", "[dev] preset: Phase 9 clutter (proc + explosive + statuses)")
    elseif id == "force_levelup" then
        devPanelState.open = false
        ctx.characterSheetOpen = false
        clearDevNpcPlacement(false)
        logRewardProfile(player, "dev_force_levelup")
        local levelup = require("src.states.levelup")
        Gamestate.push(levelup, player, function() end)
    elseif id == "reward_dump_profile" then
        logRewardProfile(player, "dev_reward_dump")
    elseif id == "reward_dump_pressure" then
        local profile = logRewardProfile(player, "dev_reward_pressure")
        local shop = ensureDevShop(ctx)
        DevLog.push("sys", string.format(
            "[reward] pressure: gold=$%d levelup_reroll=$%d shop_reroll=$%d",
            player.gold or 0,
            RewardRuntime.getRerollCost("levelup", player and player.runMetadata or nil),
            shop and shop.getRerollCost and shop:getRerollCost() or 0
        ))
        for i, item in ipairs((shop and shop.items) or {}) do
            DevLog.push("sys", string.format(
                "[reward] offer %d: %s $%s [%s/%s]",
                i,
                tostring(item.name),
                tostring(item.price),
                tostring(item.reward_bucket or "unknown"),
                tostring(item.reward_role or item.type or "unknown")
            ))
        end
        ctx.devRewardLab.profileSummary = RewardRuntime.describeProfile(profile)
    elseif id == "reward_refresh_shop" then
        local Shop = require("src.systems.shop")
        local difficulty = (ctx.roomManager and ctx.roomManager.difficulty) or 1
        ctx.devRewardLab = ctx.devRewardLab or {}
        local profile = logRewardProfile(player, "dev_reward_refresh_shop")
        ctx.devRewardLab.profileSummary = RewardRuntime.describeProfile(profile)
        ctx.devRewardLab.shop = Shop.new(difficulty, player, {
            run_metadata = player and player.runMetadata or nil,
            source = "dev_arena_shop",
            room_manager = ctx.roomManager,
            build_snapshot = RunMetadata.snapshotBuild(player, profile),
        })
        rebuildDevShopDescriptions(ctx.devRewardLab.shop)
        devRebuildPanelRows()
        devClampScroll()
        DevLog.push("sys", "[dev] refreshed dev shop offers")
        for i, item in ipairs(ctx.devRewardLab.shop.items or {}) do
            DevLog.push("sys", string.format(
                "[reward] shop %d: %s [%s/%s] %s",
                i,
                tostring(item.name),
                tostring(item.reward_bucket or "unknown"),
                tostring(item.reward_role or item.type or "unknown"),
                tostring(item.reward_reason or "no reason")
            ))
        end
    elseif id == "reward_reroll_shop" then
        local shop = ensureDevShop(ctx)
        local success, msg, cost = shop:reroll(player)
        ctx.devRewardLab.profileSummary = RewardRuntime.describeProfile(RewardRuntime.buildProfile(player, {
            source = "dev_reward_reroll_shop",
        }))
        devRebuildPanelRows()
        devClampScroll()
        if success then
            DevLog.push("sys", string.format("[dev] rerolled shop for $%d", cost or 0))
        else
            DevLog.push("sys", "[dev] shop reroll failed: " .. tostring(msg))
        end
    elseif id == "meta_dump_summary" then
        local summary = MetaRuntime.summarize(player and player.runMetadata or nil, {
            roomsCleared = ctx.roomManager and ctx.roomManager.totalRoomsCleared or 0,
            perksCount = player and player.perks and #player.perks or 0,
        })
        for _, line in ipairs(MetaRuntime.toDebugLines(summary)) do
            DevLog.push("sys", line)
        end
    elseif id == "meta_dump_retention" then
        if ctx.phase10StressWallStart and love and love.timer then
            local ms = (love.timer.getTime() - ctx.phase10StressWallStart) * 1000
            Phase10Telemetry.recordStressWallMs(ms, "phase10_preset_wall")
            ctx.phase10StressWallStart = nil
            DevLog.push("sys", string.format(
                "[phase10] stress_wall_duration_ms=%d (wall time since proc/explosion stress preset)",
                math.floor(ms + 0.5)
            ))
        end
        local rm = player and player.runMetadata
        local stats = RunMetadata.retentionStats(rm)
        DevLog.push("sys", "[meta] retention snapshot (counts vs caps):")
        for k, v in pairs(stats) do
            DevLog.push("sys", string.format("[meta]   %s = %s", tostring(k), tostring(v)))
        end
        local sm, sl = Phase10Telemetry.getLastStressSample()
        if sm then
            DevLog.push("sys", string.format("[phase10] last_stress_sample_ms=%s label=%s", tostring(sm), tostring(sl)))
        end
        DevLog.push("sys", string.format(
            "[meta]   metadata_persistence_version = %s",
            tostring(RunMetadata.METADATA_PERSISTENCE_VERSION)
        ))
    elseif id == "meta_save_snapshot" then
        local rm = player and player.runMetadata
        if not rm then
            DevLog.push("sys", "[meta] save snapshot: no run metadata")
        else
            local path = RunMetadata.defaultPersistPath()
            local ok, err = RunMetadata.saveToFile(path, rm)
            if ok then
                DevLog.push("sys", "[meta] saved run metadata snapshot to " .. tostring(path))
            else
                DevLog.push("sys", "[meta] save snapshot failed: " .. tostring(err))
            end
        end
    elseif id == "meta_dump_last_damage" then
        local rm = player and player.runMetadata
        local c = rm and rm.combat or nil
        local last = c and c.last_damage_to_player or nil
        local proc = c and c.last_major_proc or nil
        if not last then
            DevLog.push("sys", "[meta] last_damage_to_player: (none)")
        else
            DevLog.push("sys", string.format(
                "[meta] last_damage_to_player: amt=%s type=%s id=%s kind=%s fam=%s src_name=%s",
                tostring(last.amount),
                tostring(last.source_type),
                tostring(last.source_id),
                tostring(last.packet_kind),
                tostring(last.family),
                tostring(last.source_name or "-")
            ))
        end
        if not proc then
            DevLog.push("sys", "[meta] last_major_proc: (none)")
        else
            DevLog.push("sys", string.format(
                "[meta] last_major_proc: perk=%s rule=%s dmg=%s",
                tostring(proc.perk_id),
                tostring(proc.rule_id),
                tostring(proc.damage)
            ))
        end
    elseif id == "meta_open_recap" then
        if queueRunRecap then
            devPanelState.open = false
            ctx.characterSheetOpen = false
            clearDevNpcPlacement(false)
            queueRunRecap("recap", "dev_recap")
            DevLog.push("sys", "[dev] open recap")
        end
    elseif id:sub(1, 24) == "reward_apply_shop_offer:" then
        local index = tonumber(id:sub(25))
        local shop = ensureDevShop(ctx)
        rebuildDevShopDescriptions(shop)
        local item = shop.items[index or 0]
        if not item then
            DevLog.push("sys", "[dev] missing shop offer " .. tostring(index))
            return
        end
        if item.sold then
            DevLog.push("sys", "[dev] offer already applied: " .. tostring(item.name))
            return
        end
        local Shop = require("src.systems.shop")
        if Shop.applyOfferItem(item, player) then
            item.sold = true
            if player and player.runMetadata then
                local profile = RewardRuntime.buildProfile(player, { source = "dev_reward_apply_shop" })
                RewardRuntime.recordChoice(player.runMetadata, {
                    kind = "shop_purchase",
                    source = "dev_arena_shop",
                    item = item,
                    price = item.price,
                    build_snapshot = RunMetadata.snapshotBuild(player, profile),
                })
            end
            devRebuildPanelRows()
            devClampScroll()
            DevLog.push("sys", "[dev] applied shop offer: " .. tostring(item.name))
        end
    elseif id == "open_door" then
        ctx.doorOpen = true
        if currentRoom and currentRoom.door then
            currentRoom.door.locked = false
        end
        DevLog.push("sys", "[dev] door open")
    elseif id == "clear_enemies" then
        for i = #enemies, 1, -1 do
            local e = enemies[i]
            if world:hasItem(e) then world:remove(e) end
            table.remove(enemies, i)
        end
        if #enemies == 0 and not pendingEnemiesIncoming() and currentRoom and currentRoom.door then
            ctx.doorOpen = true
            currentRoom.door.locked = false
        end
        DevLog.push("sys", "[dev] cleared enemies")
    elseif id == "clear_bullets" then
        for i = #bullets, 1, -1 do
            local b = bullets[i]
            if world:hasItem(b) then world:remove(b) end
            table.remove(bullets, i)
        end
        DevLog.push("sys", "[dev] cleared bullets")
    elseif id == "spawn_bandit" or id == "spawn_nightborne"
        or id == "spawn_gunslinger" or id == "spawn_necromancer"
        or id == "spawn_buzzard" or id == "spawn_ogreboss" then
        local t = id == "spawn_bandit" and "bandit"
            or (id == "spawn_nightborne" and "nightborne")
            or (id == "spawn_gunslinger" and "gunslinger")
            or (id == "spawn_necromancer" and "necromancer")
            or (id == "spawn_buzzard" and "buzzard")
            or "ogreboss"
        startDevNpcPlacement(t)
    elseif id == "toggle_boss_fight" then
        if currentRoom then
            currentRoom.bossFight = not currentRoom.bossFight
            devRebuildPanelRows()
            devClampScroll()
            DevLog.push("sys", "[dev] boss fight " .. (currentRoom.bossFight and "on" or "off"))
        end
    elseif id == "goto_dev_arena" then
        devPanelState.open = false
        devPanelState.hover = nil
        clearDevNpcPlacement(false)
        DevLog.push("sys", "[dev] go to dev arena (new run)")
        Gamestate.switch(gameRef, { devArena = true, introCountdown = false })
    elseif id == "status_dump_player" then
        logStatusTracker("player", player.statuses)
    elseif id == "status_dump_enemy" then
        if not nearestEnemy then
            DevLog.push("sys", "[dev] no living enemy for status dump")
            return
        end
        logStatusTracker("enemy", nearestEnemy.statuses)
    elseif id == "status_clear_player" then
        Buffs.clearAll(player.statuses)
        DevLog.push("sys", "[dev] cleared player statuses")
    elseif id == "status_clear_enemy" then
        if not nearestEnemy then
            DevLog.push("sys", "[dev] no living enemy to clear")
            return
        end
        Buffs.clearAll(nearestEnemy.statuses)
        DevLog.push("sys", "[dev] cleared nearest enemy statuses")
    elseif id == "status_cleanse_player" then
        local removed = Buffs.cleanse(player.statuses, { negative = true })
        DevLog.push("sys", "[dev] cleansed player negatives: " .. tostring(removed))
    elseif id == "status_step_player_1s" or id == "status_step_player_5s" then
        local seconds = id == "status_step_player_1s" and 1 or 5
        if advanceStatusTime(player, player, "player", world, seconds) then
            DevLog.push("sys", "[dev] advanced player statuses " .. tostring(seconds) .. "s")
        end
    elseif id == "status_purge_enemy" then
        if not nearestEnemy then
            DevLog.push("sys", "[dev] no living enemy to purge")
            return
        end
        local removed = Buffs.purge(nearestEnemy.statuses, { positive = true })
        DevLog.push("sys", "[dev] purged nearest enemy positives: " .. tostring(removed))
    elseif id == "status_consume_enemy_shock" then
        if not nearestEnemy then
            DevLog.push("sys", "[dev] no living enemy to consume shock from")
            return
        end
        local removed = Buffs.consume(nearestEnemy.statuses, "shock", "consume", {
            owner_actor = nearestEnemy,
            target_kind = "enemy",
            world = world,
        })
        DevLog.push("sys", "[dev] consumed nearest enemy shock: " .. tostring(removed))
    elseif id == "status_step_enemy_1s" or id == "status_step_enemy_5s" then
        local seconds = id == "status_step_enemy_1s" and 1 or 5
        if not nearestEnemy then
            DevLog.push("sys", "[dev] no living enemy to advance statuses on")
            return
        end
        if advanceStatusTime(player, nearestEnemy, "enemy", world, seconds) then
            DevLog.push("sys", "[dev] advanced enemy statuses " .. tostring(seconds) .. "s")
        end
    elseif id:sub(1, 14) == "status_player:" then
        local status_id = id:sub(15)
        if applyDebugStatus(player, player, "player", status_id, world) then
            DevLog.push("sys", "[dev] applied " .. status_id .. " to player")
        end
    elseif id:sub(1, 13) == "status_enemy:" then
        local status_id = id:sub(14)
        if not nearestEnemy then
            DevLog.push("sys", "[dev] no living enemy for status application")
            return
        end
        if applyDebugStatus(player, nearestEnemy, "enemy", status_id, world) then
            DevLog.push("sys", "[dev] applied " .. status_id .. " to nearest enemy")
        end
    elseif id:sub(1, 4) == "gun:" then
        local gunId = id:sub(5)
        local Guns = require("src.data.guns")
        local gunDef = Guns.getById(gunId)
        if gunDef then
            local slot = player.activeWeaponSlot
            player:equipWeapon(gunDef, slot)
            DevLog.push("sys", "[dev] equipped " .. gunDef.name .. " to slot " .. slot)
        end
    elseif id:sub(1, 5) == "perk:" then
        local pid = id:sub(6)
        if devPlayerHasPerk(player, pid) then
            DevLog.push("sys", "[dev] already have perk: " .. pid)
            return
        end
        local perk = devPerkById(pid)
        if perk then
            Progression.applyPerk(player, perk)
            DevLog.push("sys", "[dev] perk " .. pid)
        end
    end
end

return { apply = apply }
