-- Dev panel actions (extracted from game.lua to stay under LuaJIT's 60-upvalue limit per function).
local Gamestate = require("lib.hump.gamestate")
local Progression = require("src.systems.progression")
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
