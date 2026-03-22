-- Dev panel actions (extracted from game.lua to stay under LuaJIT's 60-upvalue limit per function).
local Gamestate = require("lib.hump.gamestate")
local Progression = require("src.systems.progression")
local Buffs = require("src.systems.buffs")
local SourceRef = require("src.systems.source_ref")
local DevLog = require("src.ui.devlog")

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

--- ctx is game._runtime filled by game.lua before each call.
local function apply(id, ctx)
    if not DEBUG or not ctx.player or not id then return end
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
    local nearestEnemy = nearestLivingEnemy(player, enemies)

    if id:sub(1, 8) == "section:" then
        local sectionId = id:sub(9)
        if devPanelState.sections and devPanelState.sections[sectionId] ~= nil then
            devPanelState.sections[sectionId] = not devPanelState.sections[sectionId]
            devRebuildPanelRows()
            devClampScroll()
        end
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
    elseif id == "force_levelup" then
        devPanelState.open = false
        ctx.characterSheetOpen = false
        clearDevNpcPlacement(false)
        local levelup = require("src.states.levelup")
        Gamestate.push(levelup, player, function() end)
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
