-- Single `Mods` table for all requires: LuaJIT 60-upvalue closure limit (game:update).
local Mods = {
    Gamestate = require("lib.hump.gamestate"),
    Camera = require("lib.hump.camera"),
    bump = require("lib.bump"),
    Player = require("src.entities.player"),
    Enemy = require("src.entities.enemy"),
    Pickup = require("src.entities.pickup"),
    EnemyData = require("src.data.enemies"),
    Combat = require("src.systems.combat"),
    WeaponRuntime = require("src.systems.weapon_runtime"),
    Progression = require("src.systems.progression"),
    RoomManager = require("src.systems.room_manager"),
    HUD = require("src.ui.hud"),
    DevLog = require("src.ui.devlog"),
    DevPanel = require("src.ui.dev_panel"),
    DamageNumbers = require("src.ui.damage_numbers"),
    Font = require("src.ui.font"),
    WorldInteractLabel = require("src.ui.world_interact_label"),
    WorldInteractLabelBatch = require("src.ui.world_interact_label_batch"),
    Cursor = require("src.ui.cursor"),
    TextLayout = require("src.ui.text_layout"),
    ContentTooltips = require("src.systems.content_tooltips"),
    RewardRuntime = require("src.systems.reward_runtime"),
    RunMetadata = require("src.systems.run_metadata"),
    MetaRuntime = require("src.systems.meta_runtime"),
    Settings = require("src.systems.settings"),
    Keybinds = require("src.systems.keybinds"),
    SettingsPanel = require("src.ui.settings_panel"),
    Shop = require("src.systems.shop"),
    TileRenderer = require("src.systems.tile_renderer"),
    RoomProps = require("src.systems.room_props"),
    Wind = require("src.systems.wind"),
    TrainRenderer = require("src.systems.train_renderer"),
    Worlds = require("src.data.worlds"),
    GoldCoin = require("src.data.gold_coin"),
    ImpactFX = require("src.systems.impact_fx"),
    Sfx = require("src.systems.sfx"),
    MusicDirector = require("src.systems.music_director"),
    WorldLighting = require("src.systems.world_lighting"),
    Vision = require("src.data.vision"),
    GameDevApply = require("src.states.game_dev_apply"),
    combat_events = require("src.systems.combat_events"),
    damage_packet = require("src.systems.damage_packet"),
    game_rng = require("src.systems.game_rng"),
    proc_runtime = require("src.systems.proc_runtime"),
    dev_event_echo = require("src.systems.dev_event_echo"),
    presentation_runtime = require("src.systems.presentation_runtime"),
    source_ref = require("src.systems.source_ref"),
}

local WeaponsData = require("src.data.weapons")

local game = {}
game._runtime = {}

local world
local camera
local player
local bullets
local enemies
local pickups
local chests
local shrines
local croupiers
local weaponAltars
-- Packed into one table to stay under LuaJIT's 60-upvalue closure limit.
local trapEnts = { pressurePlates = {}, spikeTraps = {}, secretEntrances = {}, slotMachines = {} }
local activeCroupier
local roomManager
local currentRoom
local roomData
local shakeTimer
local shakeIntensity
local gameTimer
local doorOpen
local doorAnimFrame
local doorAnimTimer
local transitionTimer
local paused
-- Single table: LuaJIT limits closures to 60 upvalues (game:enter was over limit).
local pauseMenu = {
    view = "main", -- "main" | "settings"
    selectedIndex = 1,
    hoverIndex = nil,
    settingsTab = "video",
    settingsHover = nil,
    settingsBindCapture = nil, -- action name while waiting for a key (Controls tab)
    settingsSliderDragKey = nil,
}
local characterSheetOpen = false
--- Weapon floor: [interact] press equips nearest gun/knife; hold interact sells gun for scrap.
local weaponPickupInteractState = {}
--- True after tryInteractWorld or tryInteractPickupLoot handled interact this frame.
local worldInteractConsumed = false
--- Set in update when death completes; next draw captures world → game over (see pendingGameOver block after camera:detach).
local pendingGameOver = nil
--- When true, we're in editor test-play mode — death/door returns to editor.
local editorTestMode = false

local function classifyDamageBreakdown(payload)
    local breakdown = {}
    local source_ref = payload and payload.source_ref or {}
    local source_type = source_ref and source_ref.owner_source_type or nil
    local family = payload and payload.family or nil
    local packet_kind = payload and payload.packet_kind or nil

    if source_type == "melee" then
        breakdown.melee = true
    elseif source_type == "ultimate" then
        breakdown.ultimate = true
    elseif source_type == "perk" then
        breakdown.proc = true
    end

    if packet_kind == "delayed_secondary_hit" then
        breakdown.explosion = true
    end

    for _, tag in ipairs((payload and payload.tags) or {}) do
        if tag == "ultimate" then
            breakdown.ultimate = true
        elseif tag == "proc" then
            breakdown.proc = true
        elseif tag == "explosion" or tag == "secondary" then
            breakdown.explosion = true
        end
    end

    if family == "physical" then
        breakdown.physical = true
    elseif family == "magical" then
        breakdown.magical = true
    elseif family == "true" then
        breakdown.true_damage = true
    end

    return breakdown
end

local function buildDamageTraceDetail(payload)
    local source_ref = payload and payload.source_ref or {}
    return {
        amount = payload and payload.final_applied_damage or 0,
        source_type = source_ref and source_ref.owner_source_type or "unknown",
        source_id = source_ref and source_ref.owner_source_id or "unknown",
        parent_source_id = source_ref and source_ref.parent_source_id or nil,
        packet_kind = payload and payload.packet_kind or "unknown",
        family = payload and payload.family or "unknown",
        target_id = payload and payload.target_id or "unknown",
        tags = payload and payload.tags or {},
        room_id = currentRoom and currentRoom.id or nil,
        room_name = currentRoom and currentRoom.name or nil,
        room_index = roomManager and roomManager.currentRoomIndex or nil,
        world_id = roomManager and roomManager.worldId or nil,
        world_name = roomManager and roomManager.worldDef and roomManager.worldDef.name or nil,
    }
end

--- Incoming damage to the player: same trace shape plus readable enemy label when available.
local function buildIncomingDamageDetail(payload)
    local base = buildDamageTraceDetail(payload)
    local src = payload and payload.source_actor or nil
    if src and src.isEnemy then
        base.source_name = src.name or src.typeId
        base.enemy_type_id = src.typeId
    end
    return base
end

-- Ultimate: Dead Man's Hand (single table to avoid upvalue bloat)
local ult = { flashAlpha = 0, shotFlashScreen = 0, vignetteAlpha = 0, rings = {}, pulseTimer = 0 }
local devPanelState = {
    open = false,
    pauseGameplay = true,
    scroll = 0,
    hover = nil,
    rows = nil,
    rowsFull = nil,
    searchQuery = "",
    searchFocus = false,
    sections = nil,
}
local devNpcSpawn = nil
--- Green bump AABB overlay (only when DEBUG); toggled from dev panel
local devShowHitboxes = true
-- After touching the exit while it's locked, keep off-screen enemy arrows until the room is clear
local offScreenEnemyHintActive = false
--- Set from `game:enter` opts; used for pause restart + dev panel label.
local devArenaMode = false
local enemyNoiseEvents = {}

local PLAYER_GUNSHOT_NOISE_RADIUS = 340
local PLAYER_RELOAD_NOISE_RADIUS = 170
local PLAYER_MELEE_NOISE_RADIUS = 135
local DEV_SPAWN_COUNTS = { 1, 5, 10 }
local DEV_GROUND_SUPPORT_DEPTH = 6
local DEV_PANEL_HINT = "F1 close | ESC/right click cancel | left click world spawn | wheel scroll"
local DEV_PANEL_HELP = "F1 / ESC close  ·  click section headers  ·  wheel scroll"

local function devToolsEnabled()
    return DEBUG or DEV_TOOLS_ENABLED
end

--- Spawn world gold pickups (same as loot) instead of crediting instantly — for dev cheats.
local function spawnCheatGoldDrops(amount)
    if not amount or amount <= 0 or not player or not world then return end
    local specs, overflow = Mods.GoldCoin.pickupSpecsForTotal(amount, 28)
    if overflow > 0 then
        player:addGold(overflow, "debug_gold_overflow")
    end
    if #specs < 1 then return end
    local pw = 10
    for i = 1, #specs do
        local sp = specs[i]
        local spread = (i - 1 - (#specs - 1) * 0.5) * 18
        local px = player.x + player.w / 2 - pw / 2 + spread + (Mods.game_rng.randomFloat("game.debug_gold.px", 0, 1) - 0.5) * 8
        local py = player.y - 6 - Mods.game_rng.randomFloat("game.debug_gold.py", 0, 16)
        local p = Mods.Pickup.new(px, py, sp.type, sp.value)
        p.vy = -95 - Mods.game_rng.randomFloat("game.debug_gold.vy", 0, 70)
        p.vx = (Mods.game_rng.randomFloat("game.debug_gold.vx", 0, 1) - 0.5) * 40
        world:add(p, p.x, p.y, p.w, p.h)
        table.insert(pickups, p)
    end
end

local function handleDebugAction(action)
    if not action or not player then return end
    if action == "debug_saloon" then
        local saloon = require("src.states.saloon")
        paused = false
        pauseMenu.view = "main"
        pauseMenu.selectedIndex = 1
        pauseMenu.hoverIndex = nil
        Mods.Gamestate.push(saloon, player, roomManager)
        Mods.DevLog.push("sys", "Debug: Entered saloon")
    elseif action == "debug_add_gold" then
        spawnCheatGoldDrops(10)
        Mods.DevLog.push("sys", "Debug: +10 gold (drops)")
    elseif action == "debug_sub_gold" then
        player:spendGold(10, "dev_sub_gold")
        Mods.DevLog.push("sys", "Debug: -10 gold")
    end
end

-- Intro countdown (3→2→1) after menu: room + enemies loaded; gameplay frozen until done.
local introCD = { active = false, n = 0, segT = 0, overlayFade = 0 }
local INTRO_COUNTDOWN_SEGMENT = 0.88
local INTRO_COUNTDOWN_OVERLAY_FADE_SEC = 0.42

local function pendingEnemiesIncoming()
    return currentRoom and currentRoom.pendingEnemySpawns and #currentRoom.pendingEnemySpawns > 0
end

local devClampScroll
local devRebuildPanelRows

local function defaultDevPanelSections()
    local sections = {
        debug = false,
        player = false,
        quick = false,
        world = false,
        npc = false,
        weapons = false,
        perks = false,
        rewards = false,
        meta = false,
        statuses = false,
    }
    sections.player = true
    sections.world = true
    return sections
end

local function devBootPanelSections()
    local sections = {
        debug = false,
        player = false,
        quick = false,
        world = false,
        npc = false,
        weapons = false,
        perks = false,
        rewards = false,
        meta = false,
        statuses = false,
    }
    sections.quick = true
    sections.rewards = true
    sections.meta = true
    return sections
end

local function defaultDevNpcSpawn()
    return {
        peaceful = false,
        unarmed = false,
        countIndex = 1,
        placement = nil,
        preview = nil,
    }
end

local function getDevPanelLayout()
    return Mods.DevPanel.panelRect(GAME_WIDTH, GAME_HEIGHT)
end

local function pointInRect(x, y, rx, ry, rw, rh)
    return x >= rx and x <= rx + rw and y >= ry and y <= ry + rh
end

local function getDebugConsoleLayout()
    local panelX = GAME_WIDTH - 260
    local consoleGap = 12
    local consoleH = 240
    local consoleW = math.min(720, math.max(420, panelX - 24))
    local consoleX = math.max(12, panelX - consoleW - consoleGap)
    return consoleX, 60, consoleW, consoleH
end

local function currentDevSpawnCount()
    local idx = devNpcSpawn and devNpcSpawn.countIndex or 1
    return DEV_SPAWN_COUNTS[idx] or 1
end

local function nearestLivingEnemyLabel()
    if not player or not enemies then
        return "none"
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

    if not bestEnemy then
        return "none"
    end

    local dist = math.sqrt(bestDistSq)
    return string.format("%s  %.0fpx", bestEnemy.name or bestEnemy.typeId or "enemy", dist)
end

local function getDevSpawnLabel(typeId)
    local data = Mods.EnemyData.types[typeId]
    return data and data.name or typeId
end

local function getMouseWorldPosition()
    local mx, my = love.mouse.getPosition()
    local gx, gy = windowToGame(mx, my)
    local wx, wy = camera:worldCoords(gx, gy, 0, 0, GAME_WIDTH, GAME_HEIGHT)
    return wx, wy, gx, gy
end

local function devSpawnBlockerFilter(item)
    return item.isPlatform or item.isWall or item.isDoor or item.isEnemy or item.isPlayer
end

local function devSpawnSupportFilter(item)
    return item.isPlatform or item.isWall
end

local function supportCoverage(items, len, x, w)
    if len == 0 then return 0 end
    local spans = {}
    for i = 1, len do
        local item = items[i]
        local x1 = math.max(x, item.x)
        local x2 = math.min(x + w, item.x + item.w)
        if x2 > x1 then
            spans[#spans + 1] = { x1 = x1, x2 = x2 }
        end
    end
    if #spans == 0 then
        return 0
    end

    table.sort(spans, function(a, b) return a.x1 < b.x1 end)
    local total = 0
    local curX1 = spans[1].x1
    local curX2 = spans[1].x2
    for i = 2, #spans do
        local span = spans[i]
        if span.x1 <= curX2 then
            curX2 = math.max(curX2, span.x2)
        else
            total = total + (curX2 - curX1)
            curX1 = span.x1
            curX2 = span.x2
        end
    end
    total = total + (curX2 - curX1)
    return total
end

local function validateDevSpawnCandidate(data, x, y)
    if not world or not currentRoom then
        return false, "no room"
    end
    if x < 0 or y < 0 or x + data.width > currentRoom.width or y + data.height > currentRoom.height then
        return false, "out of bounds"
    end

    local items, len = world:queryRect(x, y, data.width, data.height, devSpawnBlockerFilter)
    if len > 0 then
        return false, "blocked"
    end

    if data.behavior ~= "flying" then
        local probeX = x + 1
        local probeW = math.max(4, data.width - 2)
        local supports, supportLen = world:queryRect(probeX, y + data.height, probeW, DEV_GROUND_SUPPORT_DEPTH, devSpawnSupportFilter)
        local coverage = supportCoverage(supports, supportLen, probeX, probeW)
        if coverage < probeW * 0.55 then
            return false, "no floor"
        end
    end

    return true, nil
end

local function buildDevSpawnPreview(typeId, worldX, worldY)
    local data = Mods.EnemyData.getScaled(typeId, roomManager and roomManager.difficulty or 1)
    if not data then
        return nil
    end

    local count = currentDevSpawnCount()
    local spacing = math.max(data.width + 10, 28)
    local center = (count - 1) * 0.5
    local candidates = {}
    local validCount = 0

    for i = 1, count do
        local offsetX = (i - 1 - center) * spacing
        local x
        local y
        if data.behavior == "flying" then
            x = math.floor(worldX + offsetX - data.width * 0.5 + 0.5)
            y = math.floor(worldY - data.height * 0.5 + 0.5)
        else
            x = math.floor(worldX + offsetX - data.width * 0.5 + 0.5)
            y = math.floor(worldY - data.height + 0.5)
        end
        local valid, reason = validateDevSpawnCandidate(data, x, y)
        if valid then
            validCount = validCount + 1
        end
        candidates[#candidates + 1] = {
            x = x,
            y = y,
            w = data.width,
            h = data.height,
            valid = valid,
            reason = reason,
        }
    end

    return {
        typeId = typeId,
        label = getDevSpawnLabel(typeId),
        data = data,
        candidates = candidates,
        totalCount = count,
        validCount = validCount,
        worldX = worldX,
        worldY = worldY,
    }
end

local function updateDevSpawnPreview(worldX, worldY)
    if not devNpcSpawn or not devNpcSpawn.placement then
        return nil
    end
    local preview = buildDevSpawnPreview(devNpcSpawn.placement.typeId, worldX, worldY)
    local previousValid = devNpcSpawn.preview and devNpcSpawn.preview.validCount or -1
    local previousX = devNpcSpawn.preview and devNpcSpawn.preview.worldX or nil
    local previousY = devNpcSpawn.preview and devNpcSpawn.preview.worldY or nil
    devNpcSpawn.preview = preview
    if devPanelState.open and preview and (previousValid ~= preview.validCount or previousX ~= preview.worldX or previousY ~= preview.worldY) then
        devRebuildPanelRows()
        devClampScroll()
    end
    return preview
end

local function clearDevNpcPlacement(pushLog)
    if devNpcSpawn and devNpcSpawn.placement and pushLog then
        Mods.DevLog.push("sys", "[dev] NPC placement cancelled")
    end
    if devNpcSpawn then
        devNpcSpawn.placement = nil
        devNpcSpawn.preview = nil
    end
end

local function startDevNpcPlacement(typeId)
    if not devNpcSpawn then
        devNpcSpawn = defaultDevNpcSpawn()
    end
    devNpcSpawn.placement = {
        typeId = typeId,
        label = getDevSpawnLabel(typeId),
    }
    local wx, wy = getMouseWorldPosition()
    updateDevSpawnPreview(wx, wy)
    Mods.DevLog.push("sys", string.format("[dev] placing %s (%sx)", getDevSpawnLabel(typeId), tostring(currentDevSpawnCount())))
    devRebuildPanelRows()
    devClampScroll()
end

local function commitDevNpcPlacement(worldX, worldY)
    local preview = updateDevSpawnPreview(worldX, worldY)
    if not preview then
        return false
    end
    if preview.validCount <= 0 then
        Mods.DevLog.push("sys", string.format("[dev] blocked spawn: %s", preview.label or preview.typeId))
        return true
    end

    local spawned = 0
    for _, candidate in ipairs(preview.candidates) do
        if candidate.valid then
            local enemy = Mods.Enemy.new(
                preview.typeId,
                candidate.x,
                candidate.y,
                roomManager and roomManager.difficulty or 1,
                {
                    peaceful = devNpcSpawn and devNpcSpawn.peaceful,
                    unarmed = devNpcSpawn and devNpcSpawn.unarmed,
                }
            )
            if enemy then
                world:add(enemy, enemy.x, enemy.y, enemy.w, enemy.h)
                enemies[#enemies + 1] = enemy
                spawned = spawned + 1
            end
        end
    end

    if spawned > 0 then
        local suffix = ""
        if devNpcSpawn and devNpcSpawn.peaceful then
            suffix = suffix .. " peaceful"
        end
        if devNpcSpawn and devNpcSpawn.unarmed then
            suffix = suffix .. " unarmed"
        end
        Mods.DevLog.push("sys", string.format("[dev] spawned %s x%d%s", preview.label or preview.typeId, spawned, suffix))
    end
    updateDevSpawnPreview(worldX, worldY)
    if devPanelState.open then
        devRebuildPanelRows()
        devClampScroll()
    end
    return true
end

local function drawDevSpawnPreview()
    local preview = devNpcSpawn and devNpcSpawn.preview
    if not preview or not preview.candidates then
        return
    end

    if not game.debugFont then
        game.debugFont = Mods.Font.new(11)
    end

    local summary = string.format(
        "%s x%d  %d/%d valid%s%s",
        preview.label or preview.typeId or "NPC",
        preview.totalCount or 1,
        preview.validCount or 0,
        preview.totalCount or 1,
        (devNpcSpawn and devNpcSpawn.peaceful) and "  peaceful" or "",
        (devNpcSpawn and devNpcSpawn.unarmed) and "  unarmed" or ""
    )

    for _, candidate in ipairs(preview.candidates) do
        local ok = candidate.valid
        local fillR, fillG, fillB = ok and 0.18 or 0.7, ok and 0.78 or 0.18, ok and 0.28 or 0.18
        local lineR, lineG, lineB = ok and 0.3 or 1.0, ok and 0.95 or 0.3, ok and 0.42 or 0.3
        love.graphics.setColor(fillR, fillG, fillB, ok and 0.18 or 0.2)
        love.graphics.rectangle("fill", candidate.x, candidate.y, candidate.w, candidate.h, 4, 4)
        love.graphics.setColor(lineR, lineG, lineB, 0.95)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", candidate.x, candidate.y, candidate.w, candidate.h, 4, 4)
        if not ok then
            love.graphics.line(candidate.x, candidate.y, candidate.x + candidate.w, candidate.y + candidate.h)
            love.graphics.line(candidate.x + candidate.w, candidate.y, candidate.x, candidate.y + candidate.h)
        end
    end
    love.graphics.setLineWidth(1)

    local anchor = preview.candidates[1]
    if anchor then
        local labelW = math.max(120, game.debugFont:getWidth(summary) + 8)
        local labelX = anchor.x + anchor.w * 0.5 - labelW * 0.5
        local labelY = anchor.y - 16
        love.graphics.setFont(game.debugFont)
        love.graphics.setColor(0, 0, 0, 0.72)
        love.graphics.rectangle("fill", labelX, labelY, labelW, 13, 4, 4)
        love.graphics.setColor(1, 0.95, 0.82, 0.98)
        love.graphics.printf(summary, labelX + 4, labelY + 1, labelW - 8, "center")
    end
end

local function drawActiveDevSpawnPreview()
    if not DEBUG or not devNpcSpawn or not devNpcSpawn.placement or not camera then
        return
    end
    local wx, wy = getMouseWorldPosition()
    updateDevSpawnPreview(wx, wy)
    drawDevSpawnPreview()
end

local function drawDevPanelOverlay()
    if not devToolsEnabled() or not devPanelState.open or not devPanelState.rows or not player then
        return
    end

    if not game.devPanelTitleFont then
        game.devPanelTitleFont = Mods.Font.new(16)
    end
    if not game.devPanelRowFont then
        game.devPanelRowFont = Mods.Font.new(13)
    end
    devClampScroll()
    local px, py, pw, ph = getDevPanelLayout()
    Mods.DevPanel.draw(devPanelState.rows, devPanelState.scroll, px, py, pw, ph, devPanelState.hover, {
        title = game.devPanelTitleFont,
        row = game.devPanelRowFont,
    }, {
        query = devPanelState.searchQuery or "",
        focused = devPanelState.searchFocus,
        hover = devPanelState.hover == Mods.DevPanel.HIT_SEARCH,
    })
end

local function emitEnemyNoise(x, y, radius, kind)
    enemyNoiseEvents[#enemyNoiseEvents + 1] = {
        x = x,
        y = y,
        radius = radius,
        kind = kind or "noise",
        age = 0,
    }
end

local function emitPlayerNoise(radius, kind)
    if not player then return end
    emitEnemyNoise(player.x + player.w * 0.5, player.y + player.h * 0.5, radius, kind)
end

local function updateEnemyNoise(dt)
    for i = #enemyNoiseEvents, 1, -1 do
        local event = enemyNoiseEvents[i]
        event.age = event.age + dt
        if event.age > 1.35 then
            table.remove(enemyNoiseEvents, i)
        end
    end
end

local function roomHasLivingThreat()
    return #enemies > 0 or pendingEnemiesIncoming()
end

local function buildMusicSnapshot()
    local pending = 0
    if currentRoom and currentRoom.pendingEnemySpawns then
        pending = #currentRoom.pendingEnemySpawns
    end
    local anyElite = false
    for _, e in ipairs(enemies) do
        if e.elite and e.alive then
            anyElite = true
            break
        end
    end
    local maxHP = player:getEffectiveStats().maxHP
    local hpRatio = maxHP > 0 and (player.hp / maxHP) or 1
    return {
        introCountdownActive = introCD.active,
        paused = paused,
        roomHasThreat = roomHasLivingThreat(),
        enemyCount = #enemies + pending,
        anyElite = anyElite,
        bossActive = currentRoom and currentRoom.bossFight or false,
        hpRatio = hpRatio,
        playerDying = player.dying,
        deathTimer = player.deathTimer or 0,
        deathDuration = Mods.Player.DEATH_DURATION,
    }
end

local function processPendingEnemySpawns(dt)
    if not currentRoom or not currentRoom.pendingEnemySpawns or not roomManager then return end
    local q = currentRoom.pendingEnemySpawns
    local i = 1
    while i <= #q do
        local e = q[i]
        e.time = e.time - dt
        if e.time <= 0 then
            local enemy = Mods.Enemy.new(e.type, e.x, e.y, roomManager.difficulty, { elite = e.elite })
            table.remove(q, i)
            if enemy then
                world:add(enemy, enemy.x, enemy.y, enemy.w, enemy.h)
                table.insert(enemies, enemy)
            end
        else
            i = i + 1
        end
    end
end

local function drawAimCrosshair()
    if not player then return end
    if not Mods.Settings.getShowCrosshair() then return end
    -- Hide in auto-gun mode when not holding primary (attack); show while LMB held so cursor aim is visible
    if player:anyAutoWeaponSlot() and player.keyboardAimMode then return end
    local px = player.x + player.w * 0.5
    local py = player.y + player.h * 0.5
    local ax = player.effectiveAimX or player.aimWorldX
    local ay = player.effectiveAimY or player.aimWorldY
    local ang = math.atan2(ay - py, ax - px)
    local cosA, sinA = math.cos(ang), math.sin(ang)
    local len = 78
    love.graphics.setColor(1, 0.92, 0.7, 0.28)
    love.graphics.setLineWidth(1)
    love.graphics.line(px, py, px + cosA * len, py + sinA * len)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end

-- Route the global debugLog used by combat.lua → Mods.DevLog combat category
function debugLog(msg)
    Mods.DevLog.push("combat", msg)
end

local function isOutOfBounds(entity, room)
    if not room then return false end
    return entity.y > room.height + 200
        or entity.y < -300
        or entity.x < -200
        or entity.x > room.width + 200
end

--- HP lost when leaving the play bounds (pit / sides); then snap to spawn.
local OUT_OF_BOUNDS_HP_PENALTY = 20

local function placePlayerAtRoomSpawn()
    if not player or not currentRoom or not world then return end
    local sp = currentRoom.playerSpawn
    if sp then
        player.x = sp.x
        player.y = sp.y
    else
        player.x = math.max(32, currentRoom.width * 0.25)
        player.y = math.max(80, currentRoom.height * 0.45)
    end
    player.vx = 0
    player.vy = 0
    player.blocking = false
    player.dropThroughTimer = 0
    world:update(player, player.x, player.y)
end

-- AABB overlap with padding (center-distance was too strict at tall doors / zoomed camera)
local DOOR_INTERACT_PAD = 10

-- Must be declared before any helper that reads it (Lua local scope starts at declaration)
local CAM_ZOOM = 3
local MAX_GAMEPLAY_ASPECT = 16 / 9

-- Dead Cells-style camera settings
local CAM_LERP_SPEED   = 5      -- how fast camera catches up (higher = snappier)
local CAM_LOOK_AHEAD_X = 60     -- pixels ahead in movement direction
local CAM_LOOK_AHEAD_Y = 30     -- pixels down when falling
local CAM_GROUNDED_Y   = -15    -- slight upward bias when grounded (see more floor ahead)
local camTargetX, camTargetY = 400, 200
local camCurrentX, camCurrentY = 400, 200

local function getGameplayCameraScale()
    return CAM_ZOOM
end

local function getGameplayViewSize()
    local scale = getGameplayCameraScale()
    return GAME_WIDTH / scale, GAME_HEIGHT / scale, scale
end

local function updateCamera(dt, snap)
    if not currentRoom or not camera or not player then return end
    local viewW, viewH, scale = getGameplayViewSize()
    camera.scale = scale
    local px = player.x + player.w / 2
    local py = player.y + player.h / 2

    -- Look-ahead: lead camera in the direction the player is moving/facing
    local lookX = 0
    if player.vx > 10 then
        lookX = CAM_LOOK_AHEAD_X
    elseif player.vx < -10 then
        lookX = -CAM_LOOK_AHEAD_X
    elseif player.facingRight then
        lookX = CAM_LOOK_AHEAD_X * 0.5
    else
        lookX = -CAM_LOOK_AHEAD_X * 0.5
    end

    -- Vertical bias: look down when falling, slight up when grounded
    local lookY = 0
    if player.grounded then
        lookY = CAM_GROUNDED_Y
    elseif player.vy > 50 then
        lookY = CAM_LOOK_AHEAD_Y
    end

    -- Target with look-ahead, clamped to room edges
    camTargetX = math.max(viewW / 2, math.min(currentRoom.width - viewW / 2, px + lookX))
    camTargetY = math.max(viewH / 2, math.min(currentRoom.height - viewH / 2, py + lookY))

    if snap then
        camCurrentX, camCurrentY = camTargetX, camTargetY
    else
        -- Smooth lerp (frame-rate independent)
        local t = 1 - math.exp(-CAM_LERP_SPEED * dt)
        camCurrentX = camCurrentX + (camTargetX - camCurrentX) * t
        camCurrentY = camCurrentY + (camTargetY - camCurrentY) * t
    end

    camera:lookAt(camCurrentX, camCurrentY)
end

local function playerOverlapsDoorAABB()
    if not currentRoom or not currentRoom.door or not player then
        return false
    end
    local door = currentRoom.door
    local pad = DOOR_INTERACT_PAD
    return player.x < door.x + door.w + pad
        and player.x + player.w > door.x - pad
        and player.y < door.y + door.h + pad
        and player.y + player.h > door.y - pad
end

local function isPlayerNearDoor()
    if not doorOpen then return false end
    return playerOverlapsDoorAABB()
end

local function enemyInCameraViewport(e, viewL, viewT, viewR, viewB)
    return e.x < viewR and e.x + e.w > viewL and e.y < viewB and e.y + e.h > viewT
end

local function rayToScreenBorder(cx, cy, dx, dy, margin)
    local w, h = GAME_WIDTH, GAME_HEIGHT
    local t = math.huge
    if dx > 1e-8 then t = math.min(t, (w - margin - cx) / dx) end
    if dx < -1e-8 then t = math.min(t, (margin - cx) / dx) end
    if dy > 1e-8 then t = math.min(t, (h - margin - cy) / dy) end
    if dy < -1e-8 then t = math.min(t, (margin - cy) / dy) end
    return t
end

local function drawExitBlockedOffscreenArrows()
    if not offScreenEnemyHintActive then return end
    local blinkOn = (math.floor(love.timer.getTime() * 5) % 2) == 0
    if not blinkOn then return end

    local camX, camY = camera:position()
    local viewW, viewH = getGameplayViewSize()
    local viewL = camX - viewW / 2
    local viewT = camY - viewH / 2
    local viewR = camX + viewW / 2
    local viewB = camY + viewH / 2

    local scx, scy = GAME_WIDTH / 2, GAME_HEIGHT / 2
    local margin = 22

    for _, e in ipairs(enemies) do
        if e.alive and not enemyInCameraViewport(e, viewL, viewT, viewR, viewB) then
            local wx = e.x + e.w / 2
            local wy = e.y + e.h / 2
            local sx, sy = camera:cameraCoords(wx, wy, 0, 0, GAME_WIDTH, GAME_HEIGHT)
            local dx, dy = sx - scx, sy - scy
            local len = math.sqrt(dx * dx + dy * dy)
            if len < 1e-4 then
                -- enemy behind / degenerate: nudge east
                dx, dy = 1, 0
                len = 1
            end
            dx, dy = dx / len, dy / len
            local t = rayToScreenBorder(scx, scy, dx, dy, margin)
            if t > 0 and t < math.huge then
                local px, py = scx + dx * t, scy + dy * t
                local tipX, tipY = px + dx * 16, py + dy * 16
                local ox, oy = -dy * 9, dx * 9
                love.graphics.setColor(1, 0.2, 0.12, 0.95)
                love.graphics.polygon("fill", tipX, tipY, px - ox, py - oy, px + ox, py + oy)
                love.graphics.setColor(1, 0.88, 0.35, 1)
                love.graphics.setLineWidth(2)
                love.graphics.polygon("line", tipX, tipY, px - ox, py - oy, px + ox, py + oy)
                love.graphics.setLineWidth(1)
            end
        end
    end
    love.graphics.setColor(1, 1, 1)
end

local function drawExitArrow()
    if not doorOpen or not currentRoom or not currentRoom.door then return end
    if isPlayerNearDoor() then return end

    local door = currentRoom.door
    local camX, camY = camera:position()
    local viewW, viewH = getGameplayViewSize()
    local viewL = camX - viewW / 2
    local viewT = camY - viewH / 2
    local viewR = camX + viewW / 2
    local viewB = camY + viewH / 2

    local wx = door.x + door.w / 2
    local wy = door.y + door.h / 2

    -- Only show arrow when door is off-screen
    if wx >= viewL and wx <= viewR and wy >= viewT and wy <= viewB then return end

    local scx, scy = GAME_WIDTH / 2, GAME_HEIGHT / 2
    local margin = 22
    local sx, sy = camera:cameraCoords(wx, wy, 0, 0, GAME_WIDTH, GAME_HEIGHT)
    local dx, dy = sx - scx, sy - scy
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1e-4 then dx, dy, len = 1, 0, 1 end
    dx, dy = dx / len, dy / len

    local t = rayToScreenBorder(scx, scy, dx, dy, margin)
    if t <= 0 or t == math.huge then return end

    local px, py = scx + dx * t, scy + dy * t
    local tipX, tipY = px + dx * 16, py + dy * 16
    local ox, oy = -dy * 9, dx * 9

    -- Pulse instead of blink — always visible but breathing
    local pulse = 0.7 + 0.3 * math.sin(love.timer.getTime() * 5)
    love.graphics.setColor(0.2, 1.0, 0.35, pulse)
    love.graphics.polygon("fill", tipX, tipY, px - ox, py - oy, px + ox, py + oy)
    love.graphics.setColor(1, 1, 1, pulse * 0.8)
    love.graphics.setLineWidth(2)
    love.graphics.polygon("line", tipX, tipY, px - ox, py - oy, px + ox, py + oy)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1)
end

--- Hook chest loot / ambush and procedural shrines, field croupiers, altars, wild pickups.
local function wireRoomEntities(roomDef)
    chests = {}
    shrines = {}
    croupiers = {}
    weaponAltars = {}
    activeCroupier = nil

    if currentRoom and currentRoom.chests then
        for _, c in ipairs(currentRoom.chests) do
            chests[#chests + 1] = c
        end
    end

    local function attachChestCallbacks(chest)
        chest.onLoot = function(drops)
            local spawnX, spawnY = chest:getSpawnPos()
            for _, drop in ipairs(drops) do
                local p = Mods.Pickup.new(spawnX - 5, spawnY, drop.type, drop.value)
                p.vx = drop.vx or 0
                p.vy = drop.vy or -130
                world:add(p, p.x, p.y, p.w, p.h)
                table.insert(pickups, p)
            end
        end
        chest.onAmbush = function(bonePiles)
            for _, bp in ipairs(bonePiles) do
                local ex = bp.x + (bp.w or 18) / 2 - 10
                local ey = bp.y + (bp.h or 28) - 28
                local skel = Mods.Enemy.new("skeleton", ex, ey, roomManager.difficulty, {})
                if skel then
                    world:add(skel, skel.x, skel.y, skel.w, skel.h)
                    table.insert(enemies, skel)
                    bp.riseProgress = 0
                    bp._skelRef = skel
                end
            end
        end
    end

    for _, chest in ipairs(chests) do
        attachChestCallbacks(chest)
    end

    if roomDef and currentRoom then
        local mapRoom = {
            platforms   = currentRoom.platforms,
            playerSpawn = roomDef.playerSpawn,
            exitDoor    = roomDef.exitDoor,
            chests      = roomDef.chests,
            secretAreas = currentRoom.secretAreas,
        }
        local MapActivities = require("src.systems.map_activities")
        local activities
        if roomDef.testRoom or roomDef.devArena then
            activities = MapActivities.generateAll(mapRoom, roomManager.difficulty, roomManager.currentRoomIndex)
        else
            activities = MapActivities.generate(mapRoom, roomManager.difficulty, roomManager.currentRoomIndex)
        end
        for _, shrine in ipairs(activities.shrines or {}) do
            shrine.onActivate = function(buffId)
                if player and player.statuses then
                    local ShrineBuffs = require("src.systems.buffs")
                    ShrineBuffs.apply(player.statuses, buffId)
                end
            end
            shrines[#shrines + 1] = shrine
        end
        for _, m in ipairs(activities.croupiers or {}) do
            croupiers[#croupiers + 1] = m
        end
        for _, altar in ipairs(activities.weaponAltars or {}) do
            altar.onChoose = function(choice)
                if not choice or not player then
                    return
                end
                if choice.kind == "gun" and choice.def then
                    player:equipWeapon(choice.def)
                end
            end
            weaponAltars[#weaponAltars + 1] = altar
        end
        for _, chest in ipairs(activities.extraChests or {}) do
            attachChestCallbacks(chest)
            chests[#chests + 1] = chest
        end
        for _, p in ipairs(activities.wildPickups or {}) do
            world:add(p, p.x, p.y, p.w, p.h)
            table.insert(pickups, p)
        end
        for _, plate in ipairs(activities.pressurePlates or {}) do
            trapEnts.pressurePlates[#trapEnts.pressurePlates + 1] = plate
        end
        for _, trap in ipairs(activities.spikeTraps or {}) do
            trapEnts.spikeTraps[#trapEnts.spikeTraps + 1] = trap
        end
        for _, se in ipairs(activities.secretEntrances or {}) do
            trapEnts.secretEntrances[#trapEnts.secretEntrances + 1] = se
        end
        for _, sm in ipairs(activities.slotMachines or {}) do
            sm.onResult = function(rtype, value)
                local spawnX = sm.x + sm.w * 0.5
                local spawnY = sm.y - 10
                if rtype == "gold" then
                    local specs, overflow = Mods.GoldCoin.pickupSpecsForTotal(value or 0, 28)
                    if overflow > 0 and player then
                        player:addGold(overflow, "field_slot_gold_overflow")
                    end
                    for gi = 1, #specs do
                        local sp = specs[gi]
                        local p = Mods.Pickup.new(spawnX + (gi - 1) * 5, spawnY, sp.type, sp.value)
                        world:add(p, p.x, p.y, p.w, p.h)
                        table.insert(pickups, p)
                    end
                elseif rtype == "xp" then
                    local p = Mods.Pickup.new(spawnX, spawnY, "xp", value)
                    world:add(p, p.x, p.y, p.w, p.h)
                    table.insert(pickups, p)
                elseif rtype == "health" then
                    local p = Mods.Pickup.new(spawnX, spawnY, "health", value)
                    world:add(p, p.x, p.y, p.w, p.h)
                    table.insert(pickups, p)
                elseif rtype == "weapon" and value then
                    local p = Mods.Pickup.new(spawnX, spawnY, "weapon", value)
                    world:add(p, p.x, p.y, p.w, p.h)
                    table.insert(pickups, p)
                elseif rtype == "damage" and player then
                    local ok, dmg = player:takeDamage(value)
                    if ok then
                        Mods.DamageNumbers.spawn(player.x + player.w * 0.5, player.y, dmg, "in")
                    end
                end
            end
            trapEnts.slotMachines[#trapEnts.slotMachines + 1] = sm
        end
    end
end

local function tryExitThroughDoor()
    if transitionTimer > 0 or not isPlayerNearDoor() or not roomManager then
        return false
    end
    -- Editor test-play: return to editor on door exit
    if editorTestMode then
        local editorState = require("src.states.editor")
        Mods.Gamestate.switch(editorState)
        return true
    end
    roomManager:onRoomCleared()
    if roomManager:isCheckpoint() then
        if game._runtime and game._runtime.runMetadata then
            Mods.RunMetadata.recordCheckpoint(game._runtime.runMetadata, {
                world_id = roomManager and roomManager.worldId or nil,
                world_name = roomManager and roomManager.worldDef and roomManager.worldDef.name or nil,
                room_index = roomManager and roomManager.currentRoomIndex or nil,
                total_cleared = roomManager and roomManager.totalRoomsCleared or nil,
                difficulty = roomManager and roomManager.difficulty or nil,
                dev_arena = roomManager and roomManager.devArenaMode == true,
            })
        end
        local saloon = require("src.states.saloon")
        Mods.Gamestate.push(saloon, player, roomManager)
        return true
    else
        transitionTimer = 0.5
        return true
    end
end

local function tryInteractWorld()
    if not player or not currentRoom or transitionTimer > 0 then return false end
    local px = player.x + player.w / 2
    local py = player.y + player.h / 2

    for _, altar in ipairs(weaponAltars) do
        if altar.state == "choosing" and altar:isNearPlayer(px, py) then
            if altar:tryChoose(player) then return true end
        end
    end
    for _, shrine in ipairs(shrines) do
        if shrine:isNearPlayer(px, py) and shrine:tryActivate(player) then
            return true
        end
    end
    for _, chest in ipairs(chests) do
        if chest:isNearPlayer(px, py) then
            local function applyCursed(dmg)
                if dmg and dmg > 0 then player:takeDamage(dmg) end
            end
            if chest:tryOpen(player, applyCursed) then return true end
        end
    end
    for _, m in ipairs(croupiers) do
        if m:isNearPlayer(px, py) and m.state == "idle" then
            if m:tryInteract() then
                activeCroupier = m
                return true
            end
        end
    end
    for _, sm in ipairs(trapEnts.slotMachines) do
        if sm:isNearPlayer(px, py) then
            if sm:tryPlay(player) then return true end
        end
    end
    return tryExitThroughDoor()
end

local bgImage
local currentTheme   -- tile theme for current world (passed to Mods.TileRenderer)

-- Saloon door sprite (384×48, 8 frames of 48×48)
local doorSheet
local doorQuads = {}
local DOOR_FRAME_SIZE = 48
local DOOR_FRAMES = 8
local DOOR_FPS = 12

function game:init()
    doorSheet = love.graphics.newImage("assets/SaloonDoor.png")
    doorSheet:setFilter("nearest", "nearest")
    local sw, sh = doorSheet:getDimensions()
    for i = 0, DOOR_FRAMES - 1 do
        doorQuads[i + 1] = love.graphics.newQuad(
            i * DOOR_FRAME_SIZE, 0, DOOR_FRAME_SIZE, DOOR_FRAME_SIZE, sw, sh
        )
    end
end

local function introCountdownDigitStyle(segT)
    local u = segT / INTRO_COUNTDOWN_SEGMENT
    local pin = math.min(1, segT / 0.24)
    local ease = 1 - (1 - pin) ^ 3
    local scale = 0.46 + 0.54 * ease
    local alpha
    if u < 0.12 then
        alpha = u / 0.12
    elseif u > 0.78 then
        alpha = math.max(0, (1 - u) / (1 - 0.78))
    else
        alpha = 1
    end
    return scale, alpha * math.min(1, ease * 1.15)
end

local function pauseMenuEntries()
    return {
        { id = "resume", label = "Resume" },
        { id = "settings", label = "Mods.Settings" },
        { id = "restart", label = "Restart" },
        { id = "main_menu", label = "Main menu" },
    }
end

local function pauseMenuButtonLayout(variant)
    local screenW, screenH = GAME_WIDTH, GAME_HEIGHT
    local bw, bh = 340, 48
    local gap = 10
    if variant == "large" then
        bw, bh = 420, 60
        gap = 12
    end
    local list = pauseMenuEntries()
    local totalH = #list * bh + (#list - 1) * gap
    local startY = screenH * 0.38 - totalH * 0.5
    local rects = {}
    for i, b in ipairs(list) do
        local y = startY + (i - 1) * (bh + gap)
        rects[i] = {
            id = b.id,
            label = b.label,
            x = (screenW - bw) * 0.5,
            y = y,
            w = bw,
            h = bh,
        }
    end
    return rects
end

local function pauseHitRect(mx, my, r)
    return mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h
end

local function pauseRestartRun()
    paused = false
    pauseMenu.view = "main"
    pauseMenu.settingsBindCapture = nil
    pauseMenu.settingsSliderDragKey = nil
    devPanelState.open = false
    devPanelState.scroll = 0
    devPanelState.hover = nil
    devShowHitboxes = true
    pendingGameOver = nil
    if devArenaMode then
        Mods.Gamestate.switch(game, { devArena = true, introCountdown = false })
    else
        Mods.Gamestate.switch(game, { introCountdown = true })
    end
end

local function pauseGoToMainMenu()
    paused = false
    pauseMenu.view = "main"
    pauseMenu.settingsBindCapture = nil
    pauseMenu.settingsSliderDragKey = nil
    devPanelState.open = false
    devPanelState.scroll = 0
    devPanelState.hover = nil
    pendingGameOver = nil
    local menu = require("src.states.menu")
    Mods.Gamestate.switch(menu)
end

local function drawCharacterSheet()
    if not player then return end
    local pad = 14
    local w, h = 332, 508
    local x, y = 18, 56
    love.graphics.setColor(0.08, 0.06, 0.05, 0.92)
    love.graphics.rectangle("fill", x, y, w, h, 8, 8)
    love.graphics.setColor(0.85, 0.65, 0.35, 0.9)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x, y, w, h, 8, 8)
    love.graphics.setLineWidth(1)
    if not game.charSheetTitleFont then
        game.charSheetTitleFont = Mods.Font.new(18)
    end
    if not game.charSheetBodyFont then
        game.charSheetBodyFont = Mods.Font.new(14)
    end
    local py = y + pad
    love.graphics.setFont(game.charSheetTitleFont)
    love.graphics.setColor(1, 0.88, 0.35)
    love.graphics.print("Character", x + pad, py)
    py = py + 26
    love.graphics.setFont(game.charSheetBodyFont)
    love.graphics.setColor(0.88, 0.82, 0.72)
    love.graphics.print(string.format("Lv %d  ·  Gold: $%d", player.level, player.gold), x + pad, py)
    py = py + 20
    love.graphics.print(string.format("XP: %d / %d", player.xp, player.xpToNext), x + pad, py)
    py = py + 22
    love.graphics.print("Perks:", x + pad, py)
    py = py + 18
    local perksList = player.perks or {}
    if #perksList == 0 then
        love.graphics.setColor(0.55, 0.52, 0.48)
        love.graphics.print("(none yet)", x + pad, py)
        py = py + 20
    else
        love.graphics.setColor(0.78, 0.85, 0.72)
        local ptext = table.concat(Mods.ContentTooltips.getPerkNames(player), ", ")
        local tw = w - 2 * pad
        local _, lines = game.charSheetBodyFont:getWrap(ptext, tw)
        love.graphics.printf(ptext, x + pad, py, tw, "left")
        py = py + #lines * game.charSheetBodyFont:getHeight() + 8
    end
    local tw = w - 2 * pad
    local function drawWrappedBulletLines(lines, color)
        love.graphics.setColor(color[1], color[2], color[3], color[4] or 1)
        for _, line in ipairs(lines or {}) do
            local text = "• " .. line
            local _, wrapped = game.charSheetBodyFont:getWrap(text, tw)
            love.graphics.printf(text, x + pad + 4, py, tw - 4, "left")
            py = py + math.max(1, #wrapped) * game.charSheetBodyFont:getHeight() + 2
        end
    end
    local function drawWrappedSectionLines(lines, color)
        drawWrappedBulletLines(lines, color)
        py = py + 4
    end
    love.graphics.setColor(0.88, 0.82, 0.72)
    love.graphics.print("Weapons:", x + pad, py)
    py = py + 18
    for slotIndex = 1, 2 do
        local slot = player.weapons and player.weapons[slotIndex] or nil
        local gun = slot and slot.gun or nil
        local slotLabel = string.format("Slot %d%s: %s",
            slotIndex,
            player.activeWeaponSlot == slotIndex and " [active]" or "",
            gun and gun.name or "Empty"
        )
        love.graphics.setColor(0.88, 0.82, 0.72)
        love.graphics.print(slotLabel, x + pad, py)
        py = py + 18
        if gun then
            drawWrappedSectionLines(Mods.ContentTooltips.getLines("gun", gun), { 0.72, 0.8, 0.88, 1 })
        else
            py = py + 4
        end
    end
    love.graphics.setColor(0.88, 0.82, 0.72)
    local function drawGearBlock(slot, label)
        local g = player.gear[slot]
        love.graphics.print(string.format("%s: %s", label, g and g.name or "—"), x + pad, py)
        py = py + 18
        if g then
            drawWrappedSectionLines(Mods.ContentTooltips.getLines("gear", g), { 0.75, 0.84, 0.74, 1 })
        end
    end
    drawGearBlock("hat", "Hat")
    drawGearBlock("vest", "Vest")
    drawGearBlock("boots", "Boots")
    do
        love.graphics.setColor(0.88, 0.82, 0.72)
        love.graphics.print("Melee (fists): when your active slot is a gun",
            x + pad, py)
        py = py + 18
        drawWrappedSectionLines(Mods.ContentTooltips.getLines("gear", WeaponsData.defaults.unarmed), { 0.75, 0.84, 0.74, 1 })
    end
    drawGearBlock("shield", "Shield")
    py = py + 22
    love.graphics.setColor(0.45, 0.45, 0.48)
    love.graphics.print("1 / 2 — drop weapon from that slot (floor pickup)", x + pad, py)
    py = py + 18
    local ck = Mods.Keybinds.formatActionKey("character")
    love.graphics.print(string.format("%s to close  ·  ESC", ck), x + pad, py)
end

devClampScroll = function()
    if not devPanelState.rows then return end
    if not game.devPanelTitleFont then
        game.devPanelTitleFont = Mods.Font.new(16)
    end
    if not game.devPanelRowFont then
        game.devPanelRowFont = Mods.Font.new(13)
    end
    local _, _, pw, ph = getDevPanelLayout()
    local maxS = Mods.DevPanel.maxScroll(devPanelState.rows, game.devPanelTitleFont, game.devPanelRowFont, pw, ph)
    devPanelState.scroll = math.max(0, math.min(maxS, devPanelState.scroll))
end

local function devApplySearchFilter()
    if not devPanelState.rowsFull then return end
    devPanelState.rows = Mods.DevPanel.filterRows(devPanelState.rowsFull, devPanelState.searchQuery or "")
    devClampScroll()
end

local function syncCurrentRoomNightMode()
    if not currentRoom or not roomManager then return end
    local want
    if roomManager.nightVisualsOverride ~= nil then
        want = roomManager.nightVisualsOverride
    else
        want = currentRoom.sourceNight == true
    end
    if want == currentRoom.nightMode then
        return
    end
    currentRoom.nightMode = want
    if want then
        if not currentRoom.fogExplored then
            local fog = Mods.Vision.initFogForRoom({ width = currentRoom.width, height = currentRoom.height })
            currentRoom.fogCellSize = fog.fogCellSize
            currentRoom.fogGridW = fog.fogGridW
            currentRoom.fogGridH = fog.fogGridH
            currentRoom.fogExplored = fog.fogExplored
            currentRoom.fogCanvasLQ = fog.fogCanvasLQ
            currentRoom.fogDirty = fog.fogDirty
        end
    else
        if currentRoom.fogCanvasLQ then
            currentRoom.fogCanvasLQ:release()
        end
        currentRoom.fogCellSize = nil
        currentRoom.fogGridW = nil
        currentRoom.fogGridH = nil
        currentRoom.fogExplored = nil
        currentRoom.fogCanvasLQ = nil
        currentRoom.fogDirty = nil
    end
end

local function queueRunRecap(outcome, source)
    if pendingGameOver or not player then
        return
    end

    local profile = Mods.RewardRuntime.buildProfile(player, {
        source = source or "run_end",
    })
    local buildSnapshot = Mods.RunMetadata.snapshotBuild(player, profile)
    local roomsCleared = roomManager and roomManager.totalRoomsCleared or 0
    local perksCount = player.perks and #player.perks or 0

    if game._runtime and game._runtime.runMetadata then
        local vis = 0
        local st = player.statuses
        if st and st.instances then
            for _ in pairs(st.instances) do
                vis = vis + 1
            end
        end
        Mods.RunMetadata.finishRun(game._runtime.runMetadata, {
            outcome = outcome or "completed",
            source = source or "run_end",
            level = player.level,
            rooms_cleared = roomsCleared,
            gold = player.gold,
            perks_count = perksCount,
            total_damage_dealt = game._runtime.runMetadata.combat
                and game._runtime.runMetadata.combat.total_damage_dealt
                or 0,
            damage_breakdown = game._runtime.runMetadata.combat
                and game._runtime.runMetadata.combat.breakdown
                or nil,
            dominant_tags = profile and profile.dominant_tags or nil,
            build_snapshot = buildSnapshot,
            visible_buff_count = vis,
        })
    end

    pendingGameOver = {
        level = player.level,
        roomsCleared = roomsCleared,
        gold = player.gold,
        perksCount = perksCount,
        runMetadata = game._runtime and game._runtime.runMetadata or nil,
        outcome = outcome or "completed",
    }
end

devRebuildPanelRows = function()
    if game._runtime and game._runtime.devRewardLab then
        game._runtime.devRewardLab.profileSummary = Mods.RewardRuntime.describeProfile(Mods.RewardRuntime.buildProfile(player, {
            source = "dev_panel",
        }))
    end
    local metaSummary = Mods.MetaRuntime.summarize(game._runtime and game._runtime.runMetadata or nil, {
        roomsCleared = roomManager and roomManager.totalRoomsCleared or 0,
        perksCount = player and player.perks and #player.perks or 0,
    })
    devPanelState.rows = Mods.DevPanel.buildRows({
        gameplayPaused = devPanelState.pauseGameplay,
        showHitboxes = devShowHitboxes,
        nightOverride = roomManager and roomManager.nightVisualsOverride,
        bossFightActive = currentRoom and currentRoom.bossFight,
        inDevArena = devArenaMode,
        sections = devPanelState.sections,
        npc = {
            peaceful = devNpcSpawn and devNpcSpawn.peaceful,
            unarmed = devNpcSpawn and devNpcSpawn.unarmed,
            count = currentDevSpawnCount(),
            placement = devNpcSpawn and devNpcSpawn.placement,
            preview = devNpcSpawn and devNpcSpawn.preview,
        },
        statusLab = {
            nearestEnemyLabel = nearestLivingEnemyLabel(),
        },
        rewardLab = {
            offers = (game._runtime.devRewardLab and game._runtime.devRewardLab.shop and game._runtime.devRewardLab.shop.items) or {},
            profileSummary = (game._runtime.devRewardLab and game._runtime.devRewardLab.profileSummary) or "none",
            gold = player and player.gold or 0,
            shopRerollCost = (game._runtime.devRewardLab and game._runtime.devRewardLab.shop and game._runtime.devRewardLab.shop.getRerollCost and game._runtime.devRewardLab.shop:getRerollCost()) or 0,
            levelupRerollCost = Mods.RewardRuntime.getRerollCost("levelup", game._runtime and game._runtime.runMetadata or nil),
        },
        metaLab = {
            summary = metaSummary,
        },
    })
    devPanelState.rowsFull = devPanelState.rows
    devPanelState.rows = Mods.DevPanel.filterRows(devPanelState.rowsFull, devPanelState.searchQuery or "")
end

do
    local function bindRuntimeHelpers()
        local r = game._runtime
        r.devRebuildPanelRows = devRebuildPanelRows
        r.devClampScroll = devClampScroll
        r.syncCurrentRoomNightMode = syncCurrentRoomNightMode
        r.clearDevNpcPlacement = clearDevNpcPlacement
        r.startDevNpcPlacement = startDevNpcPlacement
        r.getMouseWorldPosition = getMouseWorldPosition
        r.updateDevSpawnPreview = updateDevSpawnPreview
        r.currentDevSpawnCount = currentDevSpawnCount
        r.pendingEnemiesIncoming = pendingEnemiesIncoming
        r.spawnCheatGoldDrops = spawnCheatGoldDrops
        r.queueRunRecap = queueRunRecap
    end

    bindRuntimeHelpers()
    game._bindRuntimeHelpers = bindRuntimeHelpers
end

local function openDevPanel()
    if not devToolsEnabled() then return end
    if not devPanelState.sections then
        devPanelState.sections = defaultDevPanelSections()
    end
    if not devNpcSpawn then
        devNpcSpawn = defaultDevNpcSpawn()
    end
    devPanelState.open = true
    devPanelState.pauseGameplay = false
    characterSheetOpen = false
    devPanelState.scroll = 0
    devPanelState.hover = nil
    devPanelState.searchQuery = ""
    devPanelState.searchFocus = false
    devRebuildPanelRows()
    if not game.devPanelTitleFont then
        game.devPanelTitleFont = Mods.Font.new(16)
    end
    devClampScroll()
end

local function devApplyAction(id)
    if not id or id == Mods.DevPanel.HIT_SEARCH then return end
    local r = game._runtime
    r.world = world
    r.player = player
    r.enemies = enemies
    r.bullets = bullets
    r.currentRoom = currentRoom
    r.roomManager = roomManager
    r.devPanelState = devPanelState
    r.devNpcSpawn = devNpcSpawn
    r.doorOpen = doorOpen
    r.characterSheetOpen = characterSheetOpen
    r.devShowHitboxes = devShowHitboxes
    r.gameRef = game
    r.devRewardLab = game._runtime.devRewardLab
    Mods.GameDevApply.apply(id, r)
    doorOpen = r.doorOpen
    characterSheetOpen = r.characterSheetOpen
    devShowHitboxes = r.devShowHitboxes
    game._runtime.devRewardLab = r.devRewardLab
end

local function initGameplaySessionState(opts)
    introCD.active = false
    introCD.n = 0
    introCD.segT = 0
    introCD.overlayFade = 0

    world = Mods.bump.newWorld(32)
    camera = Mods.Camera(400, 200)
    camera.scale = CAM_ZOOM
    camCurrentX, camCurrentY = 400, 200
    camTargetX, camTargetY = 400, 200
    player = Mods.Player.new(50, 300)
    do
        local d = Mods.Settings.getDefaultAutoGun()
        player.autoGunSlot1 = d
        player.autoGunSlot2 = d
    end
    world:add(player, player.x, player.y, player.w, player.h)
    player.isPlayer = true

    bullets = {}
    enemies = {}
    pickups = {}
    chests = {}
    shrines = {}
    croupiers = {}
    weaponAltars = {}
    trapEnts.pressurePlates = {}
    trapEnts.spikeTraps = {}
    trapEnts.secretEntrances = {}
    trapEnts.slotMachines = {}
    activeCroupier = nil
    enemyNoiseEvents = {}
    shakeTimer = 0
    shakeIntensity = 0
    gameTimer = 0
    devPanelState.open = false
    devPanelState.pauseGameplay = false
    devPanelState.scroll = 0
    devPanelState.hover = nil
    doorOpen = false
    doorAnimFrame = 1
    doorAnimTimer = 0
    transitionTimer = 0
    paused = false
    pauseMenu.view = "main"
    pauseMenu.selectedIndex = 1
    pauseMenu.hoverIndex = nil
    pauseMenu.settingsTab = "video"
    pauseMenu.settingsHover = nil
    pauseMenu.settingsBindCapture = nil
    pauseMenu.settingsSliderDragKey = nil
    characterSheetOpen = false
    weaponPickupInteractState = {}
    worldInteractConsumed = false
    pendingGameOver = nil
    devPanelState.open = false
    devPanelState.scroll = 0
    devPanelState.hover = nil
    devPanelState.searchQuery = ""
    devPanelState.searchFocus = false
    devPanelState.rowsFull = nil
    devPanelState.rows = nil
    devPanelState.sections = (opts and opts.devBoot) and devBootPanelSections() or defaultDevPanelSections()
    devNpcSpawn = defaultDevNpcSpawn()
    devShowHitboxes = true
end

local function initGameplayRuntime(opts)
    game._runtime = {}
    Mods.combat_events.clear()
    if game._bindRuntimeHelpers then
        game._bindRuntimeHelpers()
    end
    game._runtime.runSeed = (opts and opts.runSeed) or Mods.game_rng.seedFromTime()
    game._runtime.rng = Mods.game_rng.new(game._runtime.runSeed)
    Mods.game_rng.setCurrent(game._runtime.rng)
    game._runtime.devRewardLab = {
        shop = Mods.Shop.new(1),
        profileSummary = "uninitialized",
    }
    Mods.combat_events.subscribe("OnKill", function(payload)
        if not payload or payload.target_kind ~= "enemy" then
            return
        end
        local target = payload.target_actor
        if not target or target.cc_profile ~= "boss" then
            return
        end
        if not game._runtime or not game._runtime.runMetadata then
            return
        end
        Mods.RunMetadata.recordBossKilled(game._runtime.runMetadata, target, {
            room_id = currentRoom and currentRoom.id or nil,
            room_name = currentRoom and currentRoom.name or nil,
            world_id = roomManager and roomManager.worldId or nil,
            world_name = roomManager and roomManager.worldDef and roomManager.worldDef.name or nil,
            room_index = roomManager and roomManager.currentRoomIndex or nil,
            total_cleared = roomManager and roomManager.totalRoomsCleared or nil,
            difficulty = roomManager and roomManager.difficulty or nil,
            dev_arena = roomManager and roomManager.devArenaMode == true,
        })
    end)
    Mods.combat_events.subscribe("OnDamageTaken", function(payload)
        if not payload or payload.target_kind ~= "enemy" then
            return
        end
        if payload.source_actor_kind ~= "player" then
            return
        end
        if not game._runtime or not game._runtime.runMetadata then
            return
        end
        Mods.RunMetadata.recordDamageDealt(
            game._runtime.runMetadata,
            payload.final_applied_damage,
            classifyDamageBreakdown(payload),
            buildDamageTraceDetail(payload)
        )
    end)
    Mods.combat_events.subscribe("OnDamageTaken", function(payload)
        if not payload or payload.target_kind ~= "player" then
            return
        end
        if not game._runtime or not game._runtime.runMetadata then
            return
        end
        Mods.RunMetadata.recordDamageToPlayer(game._runtime.runMetadata, buildIncomingDamageDetail(payload))
    end)
end

local function initGameplayWorld()
    world = Mods.bump.newWorld(32)
    camera = Mods.Camera(400, 200)
    camera.scale = getGameplayCameraScale()
    camCurrentX, camCurrentY = 400, 200
    camTargetX, camTargetY = 400, 200
    player = Mods.Player.new(50, 300)
    player.runMetadata = game._runtime.runMetadata
    do
        local d = Mods.Settings.getDefaultAutoGun()
        player.autoGunSlot1 = d
        player.autoGunSlot2 = d
    end
    game._runtime.procRuntime = Mods.proc_runtime.init(player)
    game._runtime.presentationRuntime = Mods.presentation_runtime.init()
    world:add(player, player.x, player.y, player.w, player.h)
    player.isPlayer = true

    bullets = {}
    enemies = {}
    pickups = {}
    enemyNoiseEvents = {}
    shakeTimer = 0
    shakeIntensity = 0
    gameTimer = 0
    Mods.Combat.setExplosiveShakeHook(function(duration, intensity)
        duration = tonumber(duration) or 0
        intensity = tonumber(intensity) or 0
        if duration <= 0 or intensity <= 0 then
            return
        end
        shakeTimer = math.max(shakeTimer or 0, duration)
        shakeIntensity = math.max(shakeIntensity or 0, intensity)
    end)
end

local function configureGameplayRun(opts)
    local worldId = (opts and opts.worldId) or Mods.Worlds.order[1]
    devArenaMode = opts and opts.devArena == true
    roomManager = Mods.RoomManager.new(worldId)
    roomManager.devArenaMode = devArenaMode
    currentTheme = roomManager:getTheme()
    Mods.TileRenderer.preloadTheme(currentTheme)

    if worldId == "train" then
        Mods.Wind.activate()
        Mods.TrainRenderer.preload()
    else
        Mods.Wind.deactivate()
    end

    local worldDef = Mods.Worlds.get(worldId)
    game._runtime.runMetadata = Mods.RunMetadata.new(game._runtime.runSeed, {
        world_id = worldId,
        world_name = worldDef and worldDef.name or worldId,
        dev_arena = opts and opts.devArena == true,
    })
    player.runMetadata = game._runtime.runMetadata
    game._runtime.devRewardLab.shop = Mods.Shop.new(roomManager.difficulty or 1, player, {
        run_metadata = game._runtime.runMetadata,
        source = "dev_arena_shop",
        room_manager = roomManager,
    })
    game._runtime.devRewardLab.profileSummary = Mods.RewardRuntime.describeProfile(Mods.RewardRuntime.buildProfile(player, {
        source = "dev_arena",
    }))
    local bgPath = worldDef and worldDef.background or Mods.Worlds.get(Mods.Worlds.order[1]).background
    bgImage = love.graphics.newImage(bgPath)
    bgImage:setWrap("repeat", "clampzero")
    return worldId, worldDef
end

local function enterInitialGameplayState(opts, worldId, worldDef)
    local editorRoom = opts and opts.editorRoom
    editorTestMode = (editorRoom ~= nil)
    if editorRoom then
        roomManager:generateSequence()
        Mods.DevLog.init()
        Mods.DevLog.push("sys", "Run seed: " .. tostring(game._runtime.runSeed), { noOverlay = true })
        Mods.DevLog.push("sys", "Editor test play", { noOverlay = true })
        currentRoom = roomManager:loadRoom(editorRoom, world, player)
        currentTheme = roomManager:getTheme()
        Mods.TileRenderer.preloadTheme(currentTheme)
        enemies = currentRoom.enemies
        wireRoomEntities(editorRoom)
        updateCamera(0, true)
    else
        roomManager:generateSequence()
        Mods.DevLog.init()
        Mods.DevLog.push("sys", "Run seed: " .. tostring(game._runtime.runSeed), { noOverlay = true })
        if devArenaMode then
            Mods.dev_event_echo.init()
            if opts and opts.devBoot then
                Mods.DevLog.push("sys", "CLI dev boot active", { noOverlay = true })
            end
            Mods.DevLog.push("sys", "Dev arena started", { noOverlay = true })
            loadNextRoom()
        else
            Mods.DevLog.push("sys", string.format("Run started — World: %s", worldDef and worldDef.name or worldId), { noOverlay = true })
            local saloonState = require("src.states.saloon")
            Mods.Gamestate.push(saloonState, player, roomManager)
        end
    end
end

local function finalizeGameplayEnter(opts)
    devRebuildPanelRows()
    if opts and opts.openDevPanel and devToolsEnabled() then
        openDevPanel()
    end

    if opts and opts.introCountdown and Mods.Gamestate.current() == game then
        introCD.active = true
        introCD.n = 3
        introCD.segT = 0
        introCD.overlayFade = 0
        if not game.introCountdownFont then
            game.introCountdownFont = Mods.Font.new(120)
        end
    end

    -- loadNextRoom may push saloon; only apply gameplay cursor if we're still the top state
    if Mods.Gamestate.current() == game then
        Mods.Cursor.setGameplay()
        Mods.MusicDirector.onEnterGameplay()
    end
end

function game:enter(_, opts)
    initGameplayRuntime(opts)
    initGameplaySessionState(opts)
    initGameplayWorld()
    local worldId, worldDef = configureGameplayRun(opts)
    enterInitialGameplayState(opts, worldId, worldDef)
    finalizeGameplayEnter(opts)
end

function game:leave()
    Mods.Cursor.setDefault()
    Mods.MusicDirector.onLeaveGameplay()
    Mods.Wind.deactivate()
end

function loadNextRoom()
    Mods.DamageNumbers.clear()
    Mods.ImpactFX.clear()
    -- Remove every bump body (forward loop on a stale snapshot can skip items → broken transitions)
    while world:countItems() > 0 do
        local items, n = world:getItems()
        if n < 1 then break end
        world:remove(items[1])
    end
    bullets = {}
    pickups = {}
    weaponPickupInteractState = {}
    worldInteractConsumed = false
    enemies = {}
    chests = {}
    shrines = {}
    croupiers = {}
    weaponAltars = {}
    trapEnts.pressurePlates = {}
    trapEnts.spikeTraps = {}
    trapEnts.secretEntrances = {}
    trapEnts.slotMachines = {}
    activeCroupier = nil
    enemyNoiseEvents = {}
    if devNpcSpawn then
        devNpcSpawn.preview = nil
    end
    doorOpen = false
    doorAnimFrame = 1
    doorAnimTimer = 0
    offScreenEnemyHintActive = false
    ult.flashAlpha = 0
    ult.shotFlashScreen = 0
    ult.vignetteAlpha = 0
    ult.rings = {}
    ult.pulseTimer = 0

    world:add(player, player.x, player.y, player.w, player.h)

    roomData = roomManager:nextRoom()
    if not roomData then
        -- Checkpoint reached
        local saloon = require("src.states.saloon")
        Mods.Gamestate.push(saloon, player, roomManager)
        return
    end

    currentRoom = roomManager:loadRoom(roomData, world, player)
    currentTheme = roomManager:getTheme()
    Mods.TileRenderer.preloadTheme(currentTheme)
    enemies = currentRoom.enemies
    wireRoomEntities(roomData)
    Mods.RunMetadata.recordRoom(game._runtime.runMetadata, currentRoom, {
        world_id = roomManager and roomManager.worldId or nil,
        room_index = roomManager.currentRoomIndex,
        total_cleared = roomManager.totalRoomsCleared,
        difficulty = roomManager.difficulty or 1,
        dev_arena = roomManager.devArenaMode == true,
    })
    game._runtime.devRewardLab.profileSummary = Mods.RewardRuntime.describeProfile(Mods.RewardRuntime.buildProfile(player, {
        source = "room_load",
    }))
    -- Snap camera to player on room load (no lerp lag)
    updateCamera(0, true)
    if roomManager.devArenaMode then
        Mods.DevLog.push("sys", string.format("Dev arena loaded  (diff %.1f)", roomManager.difficulty or 1), { noOverlay = true })
    else
        Mods.DevLog.push("sys", string.format("Room %d/%d loaded  (diff %.1f)",
            roomManager.currentRoomIndex, #roomManager.roomSequence,
            roomManager.difficulty or 1), { noOverlay = true })
    end
end

function game:resume()
    Mods.Cursor.setGameplay()
    Mods.MusicDirector.resumeGameplay()
    -- Returning from saloon -> load new cycle of rooms
    if roomManager.needsNewRooms then
        roomManager.needsNewRooms = false
        loadNextRoom()
    end
end

function game:update(dt)
    if player and roomManager then
        Mods.MusicDirector.update(dt, buildMusicSnapshot())
    end

    if paused then return end

    if devPanelState.open and devPanelState.pauseGameplay ~= false then
        if player and player.dying then
            devPanelState.open = false
            clearDevNpcPlacement(false)
        else
            return
        end
    end

    if introCD.active then
        processPendingEnemySpawns(dt)
        introCD.overlayFade = math.min(1, introCD.overlayFade + dt / INTRO_COUNTDOWN_OVERLAY_FADE_SEC)
        introCD.segT = introCD.segT + dt
        if introCD.segT >= INTRO_COUNTDOWN_SEGMENT then
            introCD.segT = 0
            introCD.n = introCD.n - 1
            if introCD.n <= 0 then
                introCD.active = false
            end
        end
        updateCamera(dt, false)
        return
    end

    gameTimer = gameTimer + dt
    updateEnemyNoise(dt)


    -- Slow-mo from dead eye
    local timeMult = 1
    if player.deadEyeTimer > 0 then
        timeMult = 0.4
        dt = dt * timeMult
    end

    -- ── Ultimate: Dead Man's Hand state machine ──
    if player.ultActive then
        -- Fade activation flash
        ult.flashAlpha = math.max(0, ult.flashAlpha - love.timer.getDelta() * 4)

        if player.ultPhase == "barrage" then
            -- Rapid-fire at marked targets (real-time pacing; world is slowed via dt below)
            player.ultShotTimer = player.ultShotTimer - love.timer.getDelta()
            if player.ultShotTimer <= 0 and player.ultShotIndex <= #player.ultTargets then
                local target = player.ultTargets[player.ultShotIndex]
                if target and target.alive then
                    local px = player.x + player.w / 2
                    local py = player.y + player.h / 2
                    local tx = target.x + target.w / 2
                    local ty = target.y + target.h / 2
                    local angle = math.atan2(ty - py, tx - px)
                    local effectiveStats = player:getEffectiveStats()
                    local source_ref = Mods.source_ref.new({
                        owner_actor_id = player.actorId or "player",
                        owner_source_type = "ultimate",
                        owner_source_id = "dead_mans_hand",
                    })
                    local base_damage = (effectiveStats.bulletDamage or 0) * 3
                    local packet = Mods.damage_packet.new({
                        kind = "direct_hit",
                        family = "physical",
                        base_min = base_damage,
                        base_max = base_damage,
                        can_crit = true,
                        counts_as_hit = true,
                        can_trigger_on_hit = true,
                        can_trigger_proc = true,
                        can_lifesteal = true,
                        source = source_ref,
                        tags = { "projectile", "ultimate" },
                        snapshot_data = {
                            source_context = {
                                base_min = base_damage,
                                base_max = base_damage,
                                damage = effectiveStats.damageMultiplier or 1,
                                physical_damage = 0,
                                magical_damage = 0,
                                true_damage = 0,
                                crit_chance = effectiveStats.critChance or 0,
                                crit_damage = effectiveStats.critDamage or 1.5,
                                armor_pen = effectiveStats.armorPen or 0,
                                magic_pen = effectiveStats.magicPen or 0,
                            },
                        },
                        metadata = {
                            explosion_radius = 60,
                            explosion_damage_scale = 0.5,
                        },
                    })
                    local b = Mods.Combat.spawnBullet(world, {
                        x = px, y = py,
                        angle = angle,
                        speed = effectiveStats.bulletSpeed * 2.0,
                        damage = base_damage,
                        explosive = true,
                        ricochet = 0,
                        ultBullet = true,
                        packet = packet,
                        source_actor = player,
                        source_ref = source_ref,
                        packet_kind = "direct_hit",
                        damage_family = "physical",
                        damage_tags = { "projectile", "ultimate" },
                    })
                    table.insert(bullets, b)
                    Mods.Sfx.play("ult_shot", { volume = 0.7 })
                    shakeTimer = 0.1
                    shakeIntensity = 4
                    -- Shockwave ring + screen flash per shot
                    table.insert(ult.rings, { x = px, y = py, r = 0, alpha = 0.9 })
                    ult.shotFlashScreen = 0.85
                end
                player.ultShotIndex = player.ultShotIndex + 1
                player.ultShotTimer = 0.28
            end
            if player.ultShotIndex > #player.ultTargets then
                player.ultPhase = "cooldown"
                player.ultTimer = 0.6
                if #player.ultTargets > 0 then
                    Mods.Sfx.play("ult_explosion")
                    shakeTimer = 0.6
                    shakeIntensity = 10
                end
            end
            -- Slow the world during barrage (ult timers use getDelta() so they're unaffected)
            dt = dt * 0.2

        elseif player.ultPhase == "cooldown" then
            player.ultTimer = player.ultTimer - love.timer.getDelta()
            ult.vignetteAlpha = math.max(0, player.ultTimer / 0.6)
            if player.ultTimer <= 0 then
                player.ultActive = false
                player.ultPhase = "none"
                ult.vignetteAlpha = 0
            end
        end
    end

    -- Shake
    if shakeTimer > 0 then
        shakeTimer = shakeTimer - dt
    end

    -- Ult visual updates (use real delta so visuals aren't stuck in slow-mo)
    local rdt = love.timer.getDelta()
    ult.pulseTimer = ult.pulseTimer + rdt
    if ult.shotFlashScreen > 0 then
        ult.shotFlashScreen = math.max(0, ult.shotFlashScreen - rdt * 7)
    end
    local ri = 1
    while ri <= #ult.rings do
        local ring = ult.rings[ri]
        ring.r = ring.r + rdt * 220
        ring.alpha = ring.alpha - rdt * 1.8
        if ring.alpha <= 0 then
            table.remove(ult.rings, ri)
        else
            ri = ri + 1
        end
    end

    -- Transition
    if transitionTimer > 0 then
        transitionTimer = transitionTimer - dt
        if transitionTimer <= 0 then
            loadNextRoom()
        end
        return
    end

    local camX, camY = camera:position()
    local _, _, gameplayScale = getGameplayViewSize()
    local halfW = GAME_WIDTH / (2 * gameplayScale)
    local halfH = GAME_HEIGHT / (2 * gameplayScale)
    local viewL, viewT = camX - halfW, camY - halfH
    local viewR, viewB = camX + halfW, camY + halfH

    -- Update wind (needs camera position for particle spawning)
    Mods.Wind.update(dt, camX, camY, halfW * 2, halfH * 2)

    if currentRoom and currentRoom.nightMode and currentRoom.fogExplored and player and not player.dying then
        Mods.Vision.markFogExplored(currentRoom, player, getGameplayCameraScale())
    end

    local autoTx, autoTy
    local mouseAimOn
    if not player.dying then
        processPendingEnemySpawns(dt)

        -- Aim point in world (same coords as shooting) for omnidirectional melee
        do
            local mx, my = love.mouse.getPosition()
            local gx, gy = windowToGame(mx, my)
            local wx, wy = camera:worldCoords(gx, gy, 0, 0, GAME_WIDTH, GAME_HEIGHT)
            player.aimWorldX = wx
            player.aimWorldY = wy
        end

        mouseAimOn = love.mouse.isDown(1)
        do
            local agPf = player:getActiveGun()
            local meleeW = agPf and agPf.weapon_kind == "melee"
            primaryFireHeld = mouseAimOn or (meleeW and Mods.Keybinds.isDown("melee"))
        end
        player.keyboardAimMode = not mouseAimOn
        local nightMode = currentRoom and currentRoom.nightMode
        autoTx, autoTy = Mods.Combat.findAutoTarget(enemies, player, world, viewL, viewT, viewR, viewB, camera, nightMode, 0, 0)
        if mouseAimOn then
            player.effectiveAimX, player.effectiveAimY = player.aimWorldX, player.aimWorldY
        elseif autoTx then
            player.effectiveAimX, player.effectiveAimY = autoTx, autoTy
        else
            player.effectiveAimX, player.effectiveAimY = player:keyboardFallbackAimPoint()
        end

        -- AK-47 (and any fire-held anim): sustained aim-fire vs keyboard-only auto-aim
        do
            local es = player:getEffectiveStats()
            local shiftShoot = love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")
            local ag = player:getActiveGun()
            local meleeWeapon = ag and ag.weapon_kind == "melee"
            local doGunShoot = player:anyAutoWeaponSlot() or (es.meleeDamage or 0) <= 0 or shiftShoot or meleeWeapon
            -- Melee weapons: no sustained "fire held" (tap-only like fists; hold does not chain attacks).
            player.inputFireHeld = not player.blocking and (
                (not meleeWeapon and mouseAimOn and doGunShoot) or (not meleeWeapon and player:anyAutoWeaponSlot() and autoTx)
            )
        end
    elseif player then
        player.inputFireHeld = false
    end

    -- Mods.Player update
    player:update(dt, world, enemies)

    do
        local px = player.x + player.w / 2
        local py = player.y + player.h / 2
        for _, chest in ipairs(chests) do
            chest:update(dt)
            for _, bp in ipairs(chest.bonePiles) do
                if bp._skelRef and bp._skelRef.alive then
                    bp.riseProgress = math.min(1, (bp.riseProgress or 0) + dt * 1.5)
                end
            end
        end
        for _, shrine in ipairs(shrines) do
            shrine:update(dt)
        end
        for _, m in ipairs(croupiers) do
            m:update(dt, px, py, player, world, pickups, currentRoom and currentRoom.platforms)
        end
        for _, altar in ipairs(weaponAltars) do
            altar:update(dt)
            if altar.state == "choosing" and altar:isNearPlayer(px, py) then
                altar:updateSelection(px, py)
            end
        end
        for _, plate in ipairs(trapEnts.pressurePlates) do
            plate:update(dt, player)
        end
        for _, trap in ipairs(trapEnts.spikeTraps) do
            trap:update(dt, player)
        end
        for _, se in ipairs(trapEnts.secretEntrances) do
            se:update(dt, player)
        end
        for _, sm in ipairs(trapEnts.slotMachines) do
            sm:update(dt)
        end
    end

    -- Mods.Wind physics: nudge player with headwind (train world only)
    if Mods.Wind.active and not player.dying and player.filter then
        local windNudge = Mods.Wind.getForce() * dt
        if windNudge ~= 0 then
            local nx, ny = world:move(player, player.x + windNudge, player.y, player.filter)
            player.x = nx
            player.y = ny
        end
        -- Mods.Wind gusts add a mild camera shake
        if Mods.Wind.isGusting() and shakeTimer <= 0 then
            shakeTimer    = 0.08
            shakeIntensity = 1.2
        end
    end

    if not player.dying then
    local i, leveledUp -- hoisted for goto (cannot jump over `local` in same block)
    -- Auto-fire: per-slot toggles; both slots try every frame (cooldown-gated); active tab does not matter.
    if player:anyAutoWeaponSlot() and not player.blocking then
        local tx, ty
        if not autoTx then
            tx, ty = nil, nil
        elseif mouseAimOn then
            tx, ty = player.aimWorldX, player.aimWorldY
        else
            tx, ty = autoTx, autoTy
        end
        if tx then
            local gunForShake
            if player:isAkimbo() then
                if player:canAnyAkimboGunFire() then
                    local bulletData = player:shoot(tx, ty)
                    gunForShake = player:getActiveGun()
                    if bulletData and #bulletData > 0 then
                        emitPlayerNoise(PLAYER_GUNSHOT_NOISE_RADIUS, "gunshot")
                        for _, data in ipairs(bulletData) do
                            local b = Mods.Combat.spawnBullet(world, data)
                            table.insert(bullets, b)
                        end
                        local gun = gunForShake
                        local cooldown = gun and gun.baseStats.shootCooldown or 0.38
                        local shakeMult = math.min(1, cooldown / 0.38)
                        shakeTimer = 0.08
                        shakeIntensity = 2 * shakeMult
                    end
                end
            else
                local pending = {}
                for slotIdx = 1, 2 do
                    local slotAuto = (slotIdx == 1) and player.autoGunSlot1 or player.autoGunSlot2
                    if not slotAuto then
                        -- skip
                    else
                    local w = player:getWeaponRuntime(slotIdx)
                    if w and w.mode == "weapon" and w.weapon_def
                        and (w.reload_timer or 0) <= 0 and (w.cooldown_timer or 0) <= 0 then
                        local canFire = (w.ammo or 0) > 0
                        if Mods.WeaponRuntime.isMeleeWeapon(w.weapon_def) then
                            canFire = true
                        end
                        if canFire then
                            local bulletData = player:shootFromSlot(slotIdx, tx, ty)
                            if bulletData and #bulletData > 0 then
                                gunForShake = gunForShake or w.weapon_def
                                for _, data in ipairs(bulletData) do
                                    pending[#pending + 1] = data
                                end
                            end
                        end
                    end
                    end
                end
                if #pending > 0 then
                    emitPlayerNoise(PLAYER_GUNSHOT_NOISE_RADIUS, "gunshot")
                    for _, data in ipairs(pending) do
                        local b = Mods.Combat.spawnBullet(world, data)
                        table.insert(bullets, b)
                    end
                    local gun = gunForShake
                    local cooldown = gun and gun.baseStats.shootCooldown or 0.38
                    local shakeMult = math.min(1, cooldown / 0.38)
                    shakeTimer = 0.08
                    shakeIntensity = 2 * shakeMult
                end
            end
        end
    end

    -- Manual hold-to-fire: ranged only. Equipped melee (knife) uses discrete taps (mouse/key) only — same as fists.
    if mouseAimOn and not player.blocking and player:getActiveGun() then
        local es = player:getEffectiveStats()
        local shiftShoot = love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")
        local ag = player:getActiveGun()
        if ag and ag.weapon_kind ~= "melee" then
        local doGunShoot = player:anyAutoWeaponSlot() or (es.meleeDamage or 0) <= 0 or shiftShoot
        if doGunShoot and not (player:anyAutoWeaponSlot() and autoTx) then
            local mx, my = player.aimWorldX, player.aimWorldY
            local bulletData = player:shoot(mx, my)
            if bulletData and #bulletData > 0 then
                emitPlayerNoise(PLAYER_GUNSHOT_NOISE_RADIUS, "gunshot")
                for _, data in ipairs(bulletData) do
                    local b = Mods.Combat.spawnBullet(world, data)
                    table.insert(bullets, b)
                end
                local gun = player:getActiveGun()
                local cooldown = gun and gun.baseStats.shootCooldown or 0.38
                local shakeMult = math.min(1, cooldown / 0.38)
                shakeTimer = 0.08
                shakeIntensity = 2 * shakeMult
            end
        end
        end
    end

    Mods.Combat.updateBullets(bullets, dt, world, enemies, player)
    if player.dying then goto skipLivingCombat end

    local autoMeleeStarted = Mods.Combat.tryAutoMelee(
        player,
        enemies,
        world,
        viewL,
        viewT,
        viewR,
        viewB,
        camera,
        currentRoom and currentRoom.nightMode,
        0,
        0
    )
    if autoMeleeStarted then
        emitPlayerNoise(PLAYER_MELEE_NOISE_RADIUS, "melee")
    end
    Mods.Combat.checkPlayerMelee(player, enemies)
    Mods.Combat.checkPlayerMeleeVegetation(player, currentRoom and currentRoom.decorProps)
    if currentRoom then
        Mods.RoomProps.updateCutVegetation(dt, currentRoom)
    end

    -- Enemies update
    local enemyContext = {
        player = player,
        enemies = enemies,
        room = currentRoom,
        noiseEvents = enemyNoiseEvents,
        time = gameTimer,
    }
    i = 1
    while i <= #enemies do
        local e = enemies[i]
            if e.alive then
                local bulletData = e:update(dt, world, enemyContext)
                if bulletData then
                    bulletData.source_ref = bulletData.source_ref or Mods.source_ref.new({
                        owner_actor_id = e.actorId or e.typeId or "enemy",
                        owner_source_type = "enemy_attack",
                        owner_source_id = e.typeId or e.name or "enemy",
                    })
                    bulletData.packet_kind = bulletData.packet_kind or "direct_hit"
                    bulletData.damage_family = bulletData.damage_family or "physical"
                    bulletData.damage_tags = bulletData.damage_tags or { "projectile", "enemy" }
                    local b = Mods.Combat.spawnBullet(world, bulletData)
                    Mods.Sfx.play("shoot", { volume = 0.35 })
                    table.insert(bullets, b)
                end
            if isOutOfBounds(e, currentRoom) then
                e.alive = false
                e.isEnemy = false
                if world:hasItem(e) then
                    world:remove(e)
                end
            end
            i = i + 1
        else
            Mods.DevLog.push("combat", string.format("Killed %s  (xp+%d)", e.name or "enemy", e.xpValue or 0))
            local enemyDrops = Mods.Combat.onEnemyKilled(e, player)
            if enemyDrops then
                for _, drop in ipairs(enemyDrops) do
                    local p = Mods.Pickup.new(drop.x, drop.y, drop.type, drop.value)
                    if drop.vx then p.vx = drop.vx end
                    if drop.vy then p.vy = drop.vy end
                    if drop.xpLaneOffset then p.xpLaneOffset = drop.xpLaneOffset end
                    if drop.xpMagnetStagger and p.xpMagnetDelay then
                        p.xpMagnetDelay = p.xpMagnetDelay + drop.xpMagnetStagger
                    end
                    world:add(p, p.x, p.y, p.w, p.h)
                    table.insert(pickups, p)
                end
            end
            if world:hasItem(e) then
                world:remove(e)
            end
            table.remove(enemies, i)
        end
    end

    -- Contact damage
    Mods.Combat.checkContactDamage(enemies, player)
    if player.dying then goto skipLivingCombat end

    -- Pickups update
    for _, p in ipairs(pickups) do
        p:update(dt, world, player.x + player.w / 2, player.y + player.h / 2)
    end

    -- Remove dead pickups
    i = 1
    while i <= #pickups do
        if not pickups[i].alive then
            if world:hasItem(pickups[i]) then
                world:remove(pickups[i])
            end
            table.remove(pickups, i)
        else
            i = i + 1
        end
    end

    weaponPickupInteractState = Mods.Combat.advanceWeaponPickupInteraction(
        dt, pickups, player, world, weaponPickupInteractState
    )
    if not Mods.Keybinds.isDown("interact") then
        worldInteractConsumed = false
    end

    -- Pickup collection (gold/xp/health — magnet only after grounded)
    leveledUp = Mods.Combat.checkPickups(pickups, player, world)

    -- Level up
    if leveledUp then
        Mods.DevLog.push("progress", "Level up → " .. player.level)
        local levelup = require("src.states.levelup")
        Mods.Gamestate.push(levelup, player, function() end)
    end

    -- Check if all enemies dead (and no staggered spawns left) -> open door
    if currentRoom and currentRoom.door and #enemies == 0 and not doorOpen and not pendingEnemiesIncoming() then
        Mods.Sfx.play("door_open")
        doorOpen = true
        doorAnimFrame = 1
        doorAnimTimer = 0
        currentRoom.door.locked = false
        Mods.DevLog.push("sys", "All enemies cleared — door open")
    end

    -- Latch off-screen enemy hints: touch locked exit once, keep arrows until room clears
    if doorOpen or (#enemies == 0 and not pendingEnemiesIncoming()) then
        offScreenEnemyHintActive = false
    elseif currentRoom and currentRoom.door and not doorOpen and roomHasLivingThreat() and playerOverlapsDoorAABB() then
        offScreenEnemyHintActive = true
    end

    -- Exit door: use interact keybind when nearby (see tryExitThroughDoor)

    -- Out of bounds: respawn at room start, lose fixed HP (unless dev god mode)
    if isOutOfBounds(player, currentRoom) then
        if player.devGodMode then
            placePlayerAtRoomSpawn()
            updateCamera(0, true)
        else
            local loss = OUT_OF_BOUNDS_HP_PENALTY
            player.hp = math.max(0, player.hp - loss)
            player.iframes = math.max(player.iframes or 0, 1.0)
            player.hurtBlinkTimer = math.max(player.hurtBlinkTimer or 0, 1.0)
            Mods.Sfx.play("hurt")
            local pcx = player.x + player.w / 2
            local pcy = player.y + player.h / 2
            Mods.DamageNumbers.spawn(pcx, pcy, loss, "out")
            Mods.DevLog.push("sys", string.format("Out of bounds —%d HP  (respawn)", loss))
            if player.hp <= 0 then
                player:beginDeath()
            else
                placePlayerAtRoomSpawn()
                updateCamera(0, true)
            end
        end
    end

    ::skipLivingCombat::
    end -- not player.dying

    Mods.DamageNumbers.update(dt)
    Mods.ImpactFX.update(dt)

    -- Animate door opening
    if doorOpen and doorAnimFrame < DOOR_FRAMES then
        doorAnimTimer = doorAnimTimer + dt
        local interval = 1 / DOOR_FPS
        if doorAnimTimer >= interval then
            doorAnimTimer = doorAnimTimer - interval
            doorAnimFrame = doorAnimFrame + 1
            if doorAnimFrame > DOOR_FRAMES then
                doorAnimFrame = DOOR_FRAMES
            end
        end
    end

    -- Mods.Player death (after collapse animation); snapshot taken in draw after world is rendered
    if player.dying and player.deathTimer >= Mods.Player.DEATH_DURATION then
        if editorTestMode then
            local editorState = require("src.states.editor")
            Mods.Gamestate.switch(editorState)
            return
        end
        if not pendingGameOver then
            Mods.DevLog.push("sys", string.format("Mods.Player died  lv%d  %d rooms  $%d",
                player.level, roomManager.totalRoomsCleared, player.gold))
            queueRunRecap("death", "player_death")
        end
        return
    end

    -- Dead Cells-style smooth camera with look-ahead
    updateCamera(dt, false)
end

function game:keypressed(key, scancode, isrepeat)
    if introCD.active then
        if key == "f1" and devToolsEnabled() then
            openDevPanel()
            return
        end
        if key == "escape" then
            local menu = require("src.states.menu")
            Mods.Gamestate.switch(menu)
        end
        return
    end

    local _, _, _, consoleH = getDebugConsoleLayout()
    if DEBUG then
        if key == "end" then
            Mods.DevLog.followConsole()
            return
        elseif key == "pageup" then
            Mods.DevLog.scrollConsole(10, consoleH)
            return
        elseif key == "pagedown" then
            Mods.DevLog.scrollConsole(-10, consoleH)
            return
        elseif key == "home" then
            Mods.DevLog.scrollConsole(9999, consoleH)
            return
        end
    end

    if devToolsEnabled() and devPanelState.open then
        if devPanelState.searchFocus and key == "backspace" then
            devPanelState.searchQuery = (devPanelState.searchQuery or ""):sub(1, -2)
            devApplySearchFilter()
            return
        end
        if devPanelState.searchFocus and key == "tab" then
            devPanelState.searchFocus = false
            return
        end
        if key == "escape" then
            if devNpcSpawn and devNpcSpawn.placement then
                clearDevNpcPlacement(true)
                devRebuildPanelRows()
                devClampScroll()
            else
                devPanelState.open = false
                devPanelState.hover = nil
                devPanelState.searchFocus = false
            end
            return
        elseif key == "f1" then
            devPanelState.open = false
            devPanelState.hover = nil
            devPanelState.searchFocus = false
            clearDevNpcPlacement(false)
            return
        end
    end

    if key == "f1" and devToolsEnabled() then
        openDevPanel()
        return
    end

    if player and player.dying then return end

    if activeCroupier then
        if activeCroupier.state == "gambling" then
            if key == "q" or key == "escape" then
                activeCroupier:closeGamble()
                activeCroupier = nil
                return
            end
            activeCroupier:onKey(key, player)
            -- If flip started, dialog closes — release input
            if activeCroupier.state ~= "gambling" then
                activeCroupier = nil
            end
            return
        end
    end

    if paused and pauseMenu.view == "settings" and pauseMenu.settingsBindCapture then
        if key == "escape" then
            pauseMenu.settingsBindCapture = nil
        else
            local normalized = Mods.Keybinds.normalizeCapturedKey(key)
            Mods.Settings.setKeybind(pauseMenu.settingsBindCapture, normalized)
            Mods.Settings.save()
            pauseMenu.settingsBindCapture = nil
        end
        return
    end

    if key == "escape" then
        if not paused and characterSheetOpen then
            characterSheetOpen = false
            return
        end
        if paused then
            if pauseMenu.view == "settings" then
                pauseMenu.view = "main"
                pauseMenu.settingsBindCapture = nil
                pauseMenu.settingsSliderDragKey = nil
            else
                paused = false
                pauseMenu.view = "main"
                pauseMenu.settingsSliderDragKey = nil
            end
        else
            paused = true
            pauseMenu.view = "main"
            pauseMenu.selectedIndex = 1
            pauseMenu.hoverIndex = nil
        end
        return
    end

    if paused then
        if pauseMenu.view == "settings" then
            if key == "backspace" then
                pauseMenu.view = "main"
                pauseMenu.settingsBindCapture = nil
                pauseMenu.settingsSliderDragKey = nil
            elseif key == "[" then
                pauseMenu.settingsTab = Mods.SettingsPanel.cycleTab(pauseMenu.settingsTab, -1)
            elseif key == "]" then
                pauseMenu.settingsTab = Mods.SettingsPanel.cycleTab(pauseMenu.settingsTab, 1)
            end
            return
        end
        local list = pauseMenuEntries()
        if key == "up" or key == "w" then
            pauseMenu.selectedIndex = pauseMenu.selectedIndex - 1
            if pauseMenu.selectedIndex < 1 then pauseMenu.selectedIndex = #list end
        elseif key == "down" or key == "s" then
            pauseMenu.selectedIndex = pauseMenu.selectedIndex + 1
            if pauseMenu.selectedIndex > #list then pauseMenu.selectedIndex = 1 end
        elseif key == "return" or key == "space" or key == "kpenter" then
            local id = list[pauseMenu.selectedIndex].id
            if id == "resume" then
                paused = false
                pauseMenu.view = "main"
            elseif id == "settings" then
                pauseMenu.view = "settings"
            elseif id == "restart" then
                pauseRestartRun()
            elseif id == "main_menu" then
                pauseGoToMainMenu()
            end
        end
        return
    end

    if not paused and characterSheetOpen and player and world and pickups then
        local dropSlot = (key == "1" or key == "kp1") and 1
            or (key == "2" or key == "kp2") and 2
            or nil
        if dropSlot then
            Mods.Combat.dropPlayerWeaponToFloor(player, world, pickups, dropSlot)
            return
        end
    end

    if Mods.Keybinds.matches("character", key) then
        characterSheetOpen = not characterSheetOpen
        return
    end
    if Mods.Keybinds.matches("ult", key) then
        if player:tryActivateUlt() then
            -- Mark all alive on-screen enemies as targets
            local camX, camY = camera:position()
            local halfW = GAME_WIDTH / (2 * camera.scale)
            local halfH = GAME_HEIGHT / (2 * camera.scale)
            for _, e in ipairs(enemies) do
                if e.alive then
                    local ex = e.x + e.w / 2
                    local ey = e.y + e.h / 2
                    if ex > camX - halfW and ex < camX + halfW and ey > camY - halfH and ey < camY + halfH then
                        table.insert(player.ultTargets, e)
                    end
                end
            end
            ult.flashAlpha = 1
            ult.vignetteAlpha = 1
            Mods.Sfx.play("ult_activate")
            Mods.Sfx.play("yeehaw", { volume = 0.92 })
            shakeTimer = 0.55
            shakeIntensity = 8
        end
        return
    end

    if Mods.Keybinds.matches("jump", key) or key == "w" or key == "up" then
        player:jump()
    end
    if Mods.Keybinds.matches("dash", key) then
        player:tryDash()
    end
    if Mods.Keybinds.matches("drop", key) or key == "down" then
        player:tryDropThrough()
    end
    if Mods.Keybinds.matches("reload", key) then
        local wasReloading = player.reloading
        player:reload()
        if not wasReloading and player.reloading then
            emitPlayerNoise(PLAYER_RELOAD_NOISE_RADIUS, "reload")
        end
    end
    if Mods.Keybinds.matches("melee", key) and not isrepeat then
        game:tryPrimaryMeleeTapFromPointer(true)
    end
    if key == "h" then
        player:spinHolster()
    end
    if key == "tab" then
        player:switchWeapon()
    end
    if Mods.Keybinds.matches("interact", key) then
        worldInteractConsumed = tryInteractWorld() == true
        if not worldInteractConsumed and player and world and pickups then
            if Mods.Combat.tryInteractPickupLoot(pickups, player, world) then
                worldInteractConsumed = true
            end
        end
    end
end

function game:mousemoved(x, y, dx, dy)
    local gx, gy = x, y
    if devToolsEnabled() and devPanelState.open and devPanelState.rows then
        if not game.devPanelTitleFont then
            game.devPanelTitleFont = Mods.Font.new(16)
        end
        if not game.devPanelRowFont then
            game.devPanelRowFont = Mods.Font.new(13)
        end
        local px, py, pw, ph = getDevPanelLayout()
        if pointInRect(gx, gy, px, py, pw, ph) then
            devPanelState.hover = Mods.DevPanel.hitTest(devPanelState.rows, gx, gy, devPanelState.scroll, px, py, pw, ph, game.devPanelTitleFont, game.devPanelRowFont)
        else
            devPanelState.hover = nil
        end
        if devNpcSpawn and devNpcSpawn.placement and camera then
            local wx, wy = camera:worldCoords(gx, gy, 0, 0, GAME_WIDTH, GAME_HEIGHT)
            updateDevSpawnPreview(wx, wy)
        end
        return
    end
    if introCD.active then return end
    if player and player.dying then return end
    if paused then
        if pauseMenu.view == "settings" and pauseMenu.settingsSliderDragKey and game.pauseMenuButtonFont then
            local v = Mods.SettingsPanel.sliderValueFromPointerX(
                GAME_WIDTH, GAME_HEIGHT, pauseMenu.settingsTab, game.pauseMenuButtonFont,
                pauseMenu.settingsSliderDragKey, gx
            )
            if v then
                Mods.Settings.setVolumeKey(pauseMenu.settingsSliderDragKey, v)
                Mods.Settings.save()
                Mods.Settings.apply()
            end
            return
        end
        pauseMenu.hoverIndex = nil
        if pauseMenu.view == "main" then
            for i, r in ipairs(pauseMenuButtonLayout("large")) do
                if pauseHitRect(gx, gy, r) then
                    pauseMenu.hoverIndex = i
                    pauseMenu.selectedIndex = i
                    break
                end
            end
        else
            if not game.pauseMenuButtonFont then
                game.pauseMenuButtonFont = Mods.Font.new(26)
            end
            local h = Mods.SettingsPanel.hitTest(GAME_WIDTH, GAME_HEIGHT, pauseMenu.settingsTab, gx, gy, game.pauseMenuButtonFont)
            if h then
                if h.kind == "tab" then
                    pauseMenu.settingsHover = { kind = "tab", id = h.id }
                elseif h.kind == "back" then
                    pauseMenu.settingsHover = { kind = "back" }
                elseif h.kind == "row" then
                    pauseMenu.settingsHover = { kind = "row", index = h.index }
                elseif h.kind == "slider" then
                    pauseMenu.settingsHover = { kind = "slider", index = h.index, key = h.key }
                end
            else
                pauseMenu.settingsHover = nil
            end
        end
        return
    end
    if not player then return end
end

--- Single implementation for primary melee tap: same pointer math for LMB and melee key (`tryMeleePrimaryMouseTap`).
--- `fromMeleeKey`: true when the melee bind was pressed (F can melee with a ranged gun even if any weapon-slot auto is on).
function game:tryPrimaryMeleeTapFromPointer(fromMeleeKey)
    if not player or not camera or player.blocking then return end
    local mx, my = love.mouse.getPosition()
    local gx, gy = windowToGame(mx, my)
    player:tryMeleePrimaryMouseTap(camera, gx, gy, GAME_WIDTH, GAME_HEIGHT, {
        fromMeleeKey = fromMeleeKey == true,
    })
end

function game:mousepressed(x, y, button)
    local gx, gy = x, y
    if devToolsEnabled() and devPanelState.open and devPanelState.rows then
        if not game.devPanelTitleFont then
            game.devPanelTitleFont = Mods.Font.new(16)
        end
        if not game.devPanelRowFont then
            game.devPanelRowFont = Mods.Font.new(13)
        end
        local px, py, pw, ph = getDevPanelLayout()
        local consoleX, consoleY, consoleW, consoleH = getDebugConsoleLayout()
        local insidePanel = pointInRect(gx, gy, px, py, pw, ph)
        local insideConsole = pointInRect(gx, gy, consoleX - 4, consoleY - 4, consoleW + 8, consoleH)
        if insidePanel then
            if button == 1 then
                local hit = Mods.DevPanel.hitTest(devPanelState.rows, gx, gy, devPanelState.scroll, px, py, pw, ph, game.devPanelTitleFont, game.devPanelRowFont)
                if hit == Mods.DevPanel.HIT_SEARCH then
                    devPanelState.searchFocus = true
                else
                    devPanelState.searchFocus = false
                    if hit then
                        devApplyAction(hit)
                    end
                end
            end
            return
        end
        if insideConsole then
            return
        end
        if devNpcSpawn and devNpcSpawn.placement and camera then
            local wx, wy = camera:worldCoords(gx, gy, 0, 0, GAME_WIDTH, GAME_HEIGHT)
            if button == 1 then
                commitDevNpcPlacement(wx, wy)
                return
            elseif button == 2 then
                clearDevNpcPlacement(true)
                devRebuildPanelRows()
                devClampScroll()
                return
            end
        end
        return
    end
    if introCD.active then return end
    if player and player.dying then return end
    if paused then
        if button ~= 1 then return end
        if pauseMenu.view == "main" then
            for _, r in ipairs(pauseMenuButtonLayout("large")) do
                if pauseHitRect(gx, gy, r) then
                    if r.id == "resume" then
                        paused = false
                        pauseMenu.view = "main"
                    elseif r.id == "settings" then
                        pauseMenu.view = "settings"
                    elseif r.id == "restart" then
                        pauseRestartRun()
                    elseif r.id == "main_menu" then
                        pauseGoToMainMenu()
                    end
                    return
                end
            end
        else
            if not game.pauseMenuButtonFont then
                game.pauseMenuButtonFont = Mods.Font.new(26)
            end
            local h = Mods.SettingsPanel.hitTest(GAME_WIDTH, GAME_HEIGHT, pauseMenu.settingsTab, gx, gy, game.pauseMenuButtonFont)
            local r = Mods.SettingsPanel.applyHit(h, player)
            if h and h.kind == "slider" then
                pauseMenu.settingsSliderDragKey = h.key
            end
            if r then
                if r.setTab then pauseMenu.settingsTab = r.setTab end
                if r.goBack then
                    pauseMenu.view = "main"
                    pauseMenu.settingsSliderDragKey = nil
                end
                if r.action then handleDebugAction(r.action) end
            end
        end
        return
    end
    if button == 1 then
        game:tryPrimaryMeleeTapFromPointer(false)
        -- Gun fire: handled each frame while LMB held (see update: manual hold-to-fire)
    end
    if button == 2 then
        local slot = Mods.HUD.hitLoadout(gx, gy, GAME_HEIGHT)
        if slot == "weapon1" then
            player.autoGunSlot1 = not player.autoGunSlot1
        elseif slot == "weapon2" then
            local g2 = player.weapons[2] and player.weapons[2].gun
            if g2 then
                player.autoGunSlot2 = not player.autoGunSlot2
            else
                player.autoMelee = not player.autoMelee
            end
        elseif slot == "shield" and player:shieldAllowsAutoBlock() then
            player.autoBlock = not player.autoBlock
        else
            local wasReloading = player.reloading
            player:reload()
            if not wasReloading and player.reloading then
                emitPlayerNoise(PLAYER_RELOAD_NOISE_RADIUS, "reload")
            end
        end
    end
end

function game:mousereleased(x, y, button)
    if button == 1 then
        pauseMenu.settingsSliderDragKey = nil
    end
end

function game:textinput(t)
    if not devToolsEnabled() or not devPanelState.open or not devPanelState.searchFocus then return end
    if t and #t > 0 then
        local q = (devPanelState.searchQuery or "") .. t
        if #q > 256 then return end
        devPanelState.searchQuery = q
        devApplySearchFilter()
    end
end

function game:wheelmoved(x, y)
    if not devToolsEnabled() then return end
    local mx, my = love.mouse.getPosition()
    local gx, gy = windowToGame(mx, my)
    local consoleX, consoleY, consoleW, consoleH = getDebugConsoleLayout()
    local overConsole = pointInRect(gx, gy, consoleX - 4, consoleY - 4, consoleW + 8, consoleH)
    if devPanelState.open then
        local px, py, pw, ph = getDevPanelLayout()
        if pointInRect(gx, gy, px, py, pw, ph) then
            devPanelState.scroll = devPanelState.scroll - y * 36
            devClampScroll()
        elseif overConsole then
            Mods.DevLog.scrollConsole(y * 3, consoleH)
        end
        return
    end
    if overConsole then
        Mods.DevLog.scrollConsole(y * 3, consoleH)
    end
end

function game:draw()
    local outputCanvas = love.graphics.getCanvas()
    local nightMode = currentRoom and currentRoom.nightMode

    -- Mods.Camera with shake
    local sx, sy = 0, 0
    if shakeTimer > 0 then
        local sk = Mods.Settings.getScreenShakeScale()
        sx = (math.random() - 0.5) * shakeIntensity * 2 * sk
        sy = (math.random() - 0.5) * shakeIntensity * 2 * sk
    end

    if nightMode then
        Mods.WorldLighting.ensure()
        love.graphics.setCanvas(Mods.WorldLighting.getWorldCanvas())
    else
        love.graphics.setCanvas(outputCanvas)
    end
    love.graphics.clear(0, 0, 0, 1)

    camera:attach(0, 0, GAME_WIDTH, GAME_HEIGHT)
    love.graphics.translate(sx, sy)
    Mods.WorldInteractLabelBatch.clear()

    -- Room background
    if currentRoom then
        local camX, camY = camera:position()

        -- Parallax background — tiles horizontally, scrolls at 30% of camera speed
        local viewW, viewH = getGameplayViewSize()
        if bgImage then
            love.graphics.setColor(1, 1, 1)
            local bgW = bgImage:getWidth()
            local bgH = bgImage:getHeight()
            local scaleY = viewH / bgH
            local scaleX = scaleY
            local scaledW = bgW * scaleX

            local scrollSpeed = 0.3
            local offsetX = camX * (1 - scrollSpeed)

            local viewLeft  = camX - viewW / 2
            local viewRight = camX + viewW / 2
            local drawY     = camY - viewH / 2

            local startX = math.floor((viewLeft - offsetX) / scaledW) * scaledW + offsetX
            for x = startX, viewRight + scaledW, scaledW do
                love.graphics.draw(bgImage, x, drawY, 0, scaleX, scaleY)
            end
        else
            love.graphics.setColor(0.15, 0.1, 0.08)
            love.graphics.rectangle("fill",
                camX - viewW, camY - viewH,
                viewW * 2, viewH * 2)
        end

        -- Western: layered mountain bands (same ground texture, darker / dimmed) behind level art
        if currentTheme and currentTheme._mountainSilhouette and currentRoom.width and currentRoom.height then
            local wsh = currentTheme._waterStripH or 0
            Mods.TileRenderer.drawWesternMountainSilhouette(
                currentRoom.width, currentRoom.height, wsh, currentTheme)
        end

        -- Rail tracks (train world — drawn behind everything else)
        if roomManager and roomManager.worldId == "train" then
            Mods.TrainRenderer.drawRails(camX, camY, viewW, viewH, currentRoom.height)
        end

        -- Water: river in floor gaps then bottom strip (desert / any theme with _waterTexture)
        if currentTheme and currentTheme._waterTexture and currentRoom.width and currentRoom.height then
            love.graphics.setColor(1, 1, 1)
            if currentRoom.waterGapRects then
                for _, wr in ipairs(currentRoom.waterGapRects) do
                    Mods.TileRenderer.drawWaterBand(wr.x, wr.y, wr.w, wr.h, currentTheme)
                end
            end
            if currentTheme._waterStripH and currentTheme._waterStripH > 0 then
                local wsX = currentRoom.waterStripX or 0
                local wsW = currentRoom.waterStripW or currentRoom.width
                Mods.TileRenderer.drawWaterBand(
                    wsX,
                    currentRoom.height - currentTheme._waterStripH,
                    wsW,
                    currentTheme._waterStripH,
                    currentTheme
                )
            end
        end

        -- Walls (left, right, ceiling)
        for _, wall in ipairs(currentRoom.walls) do
            Mods.TileRenderer.drawWall(wall.x, wall.y, wall.w, wall.h, currentTheme)
        end

        -- Platforms: train cars use the sprite renderer; others use tiles
        if roomManager and roomManager.worldId == "train" then
            Mods.TrainRenderer.drawRoomCars(currentRoom.platforms, currentRoom.height)
            -- Non-car platforms (crates, structural overhangs, etc.) still use tiles
            for _, plat in ipairs(currentRoom.platforms) do
                if not plat.trainCar then
                    if plat.h >= 32 then
                        Mods.TileRenderer.drawWall(plat.x, plat.y, plat.w, plat.h, currentTheme)
                    else
                        Mods.TileRenderer.drawPlatform(plat.x, plat.y, plat.w, plat.h, currentTheme, plat)
                    end
                end
            end
        else
        local waterStripH = currentTheme and currentTheme._waterStripH or 0
        local cliffBottom = currentRoom.height - waterStripH
        local terrainDepthOpts = { roomHeight = currentRoom.height }
        if currentTheme and currentTheme._mountainMassSupport then
            for _, plat in ipairs(currentRoom.platforms) do
                if plat.h < 32 then
                    if plat.isGapBridge then
                        Mods.TileRenderer.drawGapBridgeMountainSupports(
                            plat.x, plat.y, plat.w, plat.h, cliffBottom, currentTheme, plat)
                    else
                        Mods.TileRenderer.drawLedgeMountainSupport(
                            plat.x, plat.y, plat.w, plat.h, cliffBottom, currentTheme, plat)
                    end
                end
            end
        end
        for _, plat in ipairs(currentRoom.platforms) do
            if not plat.isGapBridge then
                if plat.h >= 32 then
                    -- Draw cliff below elevated solid platforms (mesa/butte look)
                    Mods.TileRenderer.drawPlatformCliff(plat.x, plat.y, plat.w, plat.h, cliffBottom, currentTheme, terrainDepthOpts)
                    Mods.TileRenderer.drawWall(plat.x, plat.y, plat.w, plat.h, currentTheme, terrainDepthOpts)
                else
                    Mods.TileRenderer.drawPlatform(plat.x, plat.y, plat.w, plat.h, currentTheme, plat, terrainDepthOpts)
                end
            end
        end
        for _, plat in ipairs(currentRoom.platforms) do
            if plat.isGapBridge then
                Mods.TileRenderer.drawPlatform(plat.x, plat.y, plat.w, plat.h, currentTheme, plat, terrainDepthOpts)
            end
        end
        end  -- end train/non-train platform branch

        Mods.RoomProps.drawDecor(currentRoom)

        -- Secret entrance walls drawn before entities (they're part of the environment)
        for _, se in ipairs(trapEnts.secretEntrances) do
            se:draw()
        end

        if player then
            local px = player.x + player.w / 2
            local py = player.y + player.h / 2
            for _, trap in ipairs(trapEnts.spikeTraps) do
                trap:draw()
            end
            for _, plate in ipairs(trapEnts.pressurePlates) do
                plate:draw()
            end
            for _, shrine in ipairs(shrines) do
                shrine:draw(shrine:isNearPlayer(px, py))
            end
            for _, m in ipairs(croupiers) do
                m:draw(m:isNearPlayer(px, py), player.gold)
            end
            for _, altar in ipairs(weaponAltars) do
                altar:draw(altar:isNearPlayer(px, py))
            end
            for _, chest in ipairs(chests) do
                chest:draw(player, chest:isNearPlayer(px, py))
            end
            for _, sm in ipairs(trapEnts.slotMachines) do
                sm:draw(sm:isNearPlayer(px, py))
            end
        end

        -- Door (saloon door sprite)
        local door = currentRoom.door
        if door and doorSheet then
            local frame = doorOpen and doorAnimFrame or 1
            local quad = doorQuads[frame]
            if quad then
                love.graphics.setColor(1, 1, 1)
                -- Center the 48×48 sprite on the door hitbox
                local scale = 1
                local drawX = door.x + door.w / 2 - (DOOR_FRAME_SIZE * scale) / 2
                local drawY = door.y + door.h - DOOR_FRAME_SIZE * scale
                love.graphics.draw(doorSheet, quad, drawX, drawY, 0, scale, scale)
            end

            local doorTopY = door.y + door.h - DOOR_FRAME_SIZE
            local doorCx = door.x + door.w * 0.5

            if not doorOpen and roomHasLivingThreat() then
                Mods.WorldInteractLabel.drawAboveAnchor(doorCx, doorTopY, "Locked", {
                    bobAmp = 0.6,
                    bobTime = love.timer.getTime(),
                    fg = { 1, 0.82, 0.38 },
                    alpha = 0.9,
                })
            end

            if doorOpen then
                if player and isPlayerNearDoor() then
                    local ik = Mods.Keybinds.formatActionKey("interact")
                    Mods.WorldInteractLabel.drawAboveAnchor(doorCx, doorTopY, string.format("[%s] Exit", ik), {
                        bobAmp = 0.8,
                        bobTime = love.timer.getTime(),
                        alpha = 0.95,
                    })
                else
                    Mods.WorldInteractLabel.drawAboveAnchor(doorCx, doorTopY, "Exit", {
                        bobAmp = 0.6,
                        bobTime = love.timer.getTime(),
                        alpha = 0.88,
                    })
                end
            end
        end

        if nightMode then
            local _, _, gameplayScale = getGameplayViewSize()
            local fogHalfW = GAME_WIDTH / (2 * gameplayScale)
            local fogHalfH = GAME_HEIGHT / (2 * gameplayScale)
            local fogVL, fogVT = camX - fogHalfW, camY - fogHalfH
            local fogVR, fogVB = camX + fogHalfW, camY + fogHalfH
            Mods.Vision.drawFogOfWar(currentRoom, fogVL, fogVT, fogVR, fogVB)
        end
    end

    -- Pickups
    for _, p in ipairs(pickups) do
        p:draw(player, camera, sx, sy, currentRoom, pickups)
    end
    Mods.WorldInteractLabelBatch.flush()

    -- Enemies
    for _, e in ipairs(enemies) do
        e:draw(player, camera, sx, sy, currentRoom)
    end

    -- Mods.Player
    player:draw()
    if not introCD.active then
        drawAimCrosshair()
    end

    -- Bullets
    for _, b in ipairs(bullets) do
        b:draw()
    end

    Mods.ImpactFX.draw()
    Mods.DamageNumbers.draw()

    -- Mods.Wind particles (world-space, drawn over entities but under Mods.HUD)
    Mods.Wind.draw()

    drawActiveDevSpawnPreview()
    -- Ult world-space effects: shockwave rings + target reticles
    if (player.ultActive and player.ultPhase ~= "cooldown") or #ult.rings > 0 then
        local t = ult.pulseTimer
        -- Shockwave rings
        for _, ring in ipairs(ult.rings) do
            local px2 = player.x + player.w / 2
            local py2 = player.y + player.h / 2
            love.graphics.setLineWidth(3)
            love.graphics.setColor(1, 0.75, 0.15, ring.alpha * 0.9)
            love.graphics.circle("line", px2, py2, ring.r)
            love.graphics.setLineWidth(1.5)
            love.graphics.setColor(1, 1, 1, ring.alpha * 0.4)
            love.graphics.circle("line", px2, py2, ring.r * 0.85)
        end
        love.graphics.setLineWidth(1)
        -- Target reticles on marked enemies
        if player.ultActive then
            for i, e in ipairs(player.ultTargets) do
                if e.alive then
                    local ex = e.x + e.w / 2
                    local ey = e.y + e.h / 2
                    local pulse = math.sin(t * 9 + i * 1.3)
                    local sz = 16 + pulse * 3
                    local ra = 0.7 + pulse * 0.3
                    -- Outer circle
                    love.graphics.setColor(1, 0.1, 0.05, ra * 0.6)
                    love.graphics.setLineWidth(2)
                    love.graphics.circle("line", ex, ey, sz)
                    -- Inner dot
                    love.graphics.setColor(1, 0.3, 0.1, ra)
                    love.graphics.circle("fill", ex, ey, 2.5)
                    -- Crosshair lines (with gap)
                    local gap = sz * 0.35
                    love.graphics.setColor(1, 0.15, 0.05, ra)
                    love.graphics.setLineWidth(1.5)
                    love.graphics.line(ex - sz, ey, ex - gap, ey)
                    love.graphics.line(ex + gap, ey, ex + sz, ey)
                    love.graphics.line(ex, ey - sz, ex, ey - gap)
                    love.graphics.line(ex, ey + gap, ex, ey + sz)
                end
            end
        end
        love.graphics.setLineWidth(1)
        love.graphics.setColor(1, 1, 1)
    end

    -- Debug: bump collision AABBs (toggle in dev panel when DEBUG); omit from death snapshot
    if DEBUG and devShowHitboxes and not pendingGameOver then
        love.graphics.setColor(0, 1, 0, 0.3)
        local items, len = world:getItems()
        for i = 1, len do
            local x, y, w, h = world:getRect(items[i])
            love.graphics.rectangle("line", x, y, w, h)
        end
    end

    camera:detach()

    love.graphics.setCanvas(outputCanvas)
    if nightMode then
        do
            local pos = (player and camera) and Mods.WorldLighting.computeLightPositions(camera, player, sx, sy) or {
                lightPos0 = { 0.5, 0.55 },
                lightPos1 = { 0.5, 0.22 },
                lightForward0 = { 1, 0 },
            }
            local staticPack = {}
            if camera and currentRoom and currentRoom.staticLights then
                staticPack = Mods.WorldLighting.computeStaticLightPack(camera, currentRoom.staticLights, sx, sy)
            end
            Mods.WorldLighting.apply(Mods.WorldLighting.getWorldCanvas(), {
                lightPos0 = pos.lightPos0,
                lightPos1 = pos.lightPos1,
                lightForward0 = pos.lightForward0,
                staticLightPack = staticPack,
            })
        end
    end

    if pendingGameOver then
        -- Canvas must not be active when reading pixels; batch must be flushed first or read is often all black.
        local c = love.graphics.getCanvas()
        local snapshot = nil
        if c then
            if love.graphics.flush then
                love.graphics.flush()
            end
            love.graphics.setCanvas()
            local cw, ch = c:getWidth(), c:getHeight()
            local ok, id = pcall(function() return c:newImageData(0, 0, cw, ch) end)
            love.graphics.setCanvas(c)
            if ok and id then
                local okImg, img = pcall(love.graphics.newImage, id)
                if okImg and img then
                    snapshot = img
                end
            end
        end
        local args = {
            level = pendingGameOver.level,
            roomsCleared = pendingGameOver.roomsCleared,
            gold = pendingGameOver.gold,
            perksCount = pendingGameOver.perksCount,
            runMetadata = pendingGameOver.runMetadata,
            outcome = pendingGameOver.outcome,
            backgroundImage = snapshot,
        }
        pendingGameOver = nil
        local gameover = require("src.states.gameover")
        Mods.Gamestate.switch(gameover, args)
        local cur = Mods.Gamestate.current()
        if cur and cur.draw then
            cur:draw(cur)
        end
        return
    end

    if not introCD.active then
        -- Near locked exit + surviving enemies off-screen: blink arrows on viewport edge (screen space)
        drawExitBlockedOffscreenArrows()
        drawExitArrow()

        -- Mods.HUD (screen space)
        Mods.HUD.draw(player)
        Mods.DamageNumbers.drawHudXp()
        Mods.DamageNumbers.drawHudGold(player, camera)
        if DEBUG then
            Mods.HUD.drawReadabilityTierDebug(GAME_WIDTH, GAME_HEIGHT)
        end
        if not DEBUG then
            Mods.DevLog.drawOverlay(GAME_WIDTH, GAME_HEIGHT)
        end
        if roomManager then
            Mods.HUD.drawRoomInfo(roomManager.currentRoomIndex, #roomManager.roomSequence)
        end

        if activeCroupier and activeCroupier.state == "gambling" then
            activeCroupier:drawGambleUI(GAME_WIDTH / 2, GAME_HEIGHT - 8, player.gold, GAME_WIDTH)
        end

        -- Transition fade
        if transitionTimer > 0 then
            local alpha = 1 - (transitionTimer / 0.5)
            love.graphics.setColor(0, 0, 0, alpha)
            love.graphics.rectangle("fill", 0, 0, GAME_WIDTH, GAME_HEIGHT)
        end

        Mods.HUD.drawDeadEye(player)

        -- ── Ultimate: Dead Man's Hand overlay ──
        if player.ultActive or ult.flashAlpha > 0 or ult.shotFlashScreen > 0 or ult.vignetteAlpha > 0 then
            love.graphics.push()
            love.graphics.origin()

            -- Warm sepia during barrage — tints the world without blocking it
            if player.ultActive and player.ultPhase == "barrage" then
                love.graphics.setColor(0.55, 0.25, 0.05, 0.22)
                love.graphics.rectangle("fill", 0, 0, GAME_WIDTH, GAME_HEIGHT)
            end

            -- Red vignette edges (persists through barrage and fades in cooldown)
            if ult.vignetteAlpha > 0 then
                local va = ult.vignetteAlpha
                for vi = 1, 5 do
                    local vr = vi / 5
                    love.graphics.setColor(0.7, 0.05, 0.0, 0.14 * (1 - vr * 0.5) * va)
                    love.graphics.setLineWidth(GAME_WIDTH * 0.09 * vr)
                    love.graphics.rectangle("line",
                        GAME_WIDTH * 0.045 * vr, GAME_HEIGHT * 0.045 * vr,
                        GAME_WIDTH * (1 - 0.09 * vr), GAME_HEIGHT * (1 - 0.09 * vr))
                end
                love.graphics.setLineWidth(1)
            end

            -- Bright flash on activation
            if ult.flashAlpha > 0 then
                love.graphics.setColor(1, 0.88, 0.65, ult.flashAlpha * 0.9)
                love.graphics.rectangle("fill", 0, 0, GAME_WIDTH, GAME_HEIGHT)
            end

            -- Orange flash per barrage shot
            if ult.shotFlashScreen > 0 then
                love.graphics.setColor(1, 0.42, 0.0, ult.shotFlashScreen * 0.28)
                love.graphics.rectangle("fill", 0, 0, GAME_WIDTH, GAME_HEIGHT)
            end

            love.graphics.pop()
            love.graphics.setColor(1, 1, 1)
        end

        if characterSheetOpen and not paused then
            love.graphics.setColor(0, 0, 0, 0.35)
            love.graphics.rectangle("fill", 0, 0, GAME_WIDTH, GAME_HEIGHT)
            drawCharacterSheet()
        end

        if paused then
            love.graphics.setColor(0, 0, 0, 0.48)
            love.graphics.rectangle("fill", 0, 0, GAME_WIDTH, GAME_HEIGHT)

            if not game.pauseTitleFont then
                game.pauseTitleFont = Mods.Font.new(32)
            end
            if not game.pauseMenuButtonFont then
                game.pauseMenuButtonFont = Mods.Font.new(26)
            end
            if not game.pauseHintFont then
                game.pauseHintFont = Mods.Font.new(15)
            end
            if not game.pauseSettingsBodyFont then
                game.pauseSettingsBodyFont = Mods.Font.new(16)
            end

            if pauseMenu.view == "main" then
                love.graphics.setFont(game.pauseTitleFont)
                love.graphics.setColor(1, 0.86, 0.28, 0.95)
                love.graphics.printf("PAUSED", 0, GAME_HEIGHT * 0.16, GAME_WIDTH, "center")

                local rects = pauseMenuButtonLayout("large")
                for i, r in ipairs(rects) do
                    local hover = (pauseMenu.hoverIndex == i) or (pauseMenu.hoverIndex == nil and pauseMenu.selectedIndex == i)
                    if hover then
                        love.graphics.setColor(0.22, 0.14, 0.08, 0.92)
                    else
                        love.graphics.setColor(0.12, 0.08, 0.06, 0.75)
                    end
                    love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 6, 6)
                    love.graphics.setColor(0.85, 0.65, 0.35, hover and 1 or 0.65)
                    love.graphics.setLineWidth(2)
                    love.graphics.rectangle("line", r.x, r.y, r.w, r.h, 6, 6)
                    love.graphics.setLineWidth(1)
                    love.graphics.setColor(1, 0.95, 0.82)
                    love.graphics.setFont(game.pauseMenuButtonFont)
                    love.graphics.printf(
                        r.label,
                        r.x,
                        Mods.TextLayout.printfYCenteredInRect(game.pauseMenuButtonFont, r.y, r.h),
                        r.w,
                        "center"
                    )
                end

                love.graphics.setFont(game.pauseHintFont)
                love.graphics.setColor(0.45, 0.45, 0.48)
                love.graphics.printf("Arrows / mouse  ·  Enter  ·  ESC to resume", 0, GAME_HEIGHT * 0.88, GAME_WIDTH, "center")
            else
                Mods.SettingsPanel.draw(GAME_WIDTH, GAME_HEIGHT, pauseMenu.settingsTab, {
                    title = game.pauseTitleFont,
                    tab = game.pauseMenuButtonFont,
                    row = game.pauseSettingsBodyFont,
                    hint = game.pauseHintFont,
                }, pauseMenu.settingsHover, pauseMenu.settingsBindCapture)
            end
        end
    else
        love.graphics.setColor(0.02, 0.02, 0.04, 0.52 + (0.74 - 0.52) * introCD.overlayFade)
        love.graphics.rectangle("fill", 0, 0, GAME_WIDTH, GAME_HEIGHT)

        local sc, a = introCountdownDigitStyle(introCD.segT)
        love.graphics.push()
        love.graphics.translate(GAME_WIDTH * 0.5, GAME_HEIGHT * 0.48)
        love.graphics.scale(sc)
        love.graphics.setColor(1, 0.86, 0.28, a)
        love.graphics.setFont(game.introCountdownFont)
        local fh = game.introCountdownFont:getHeight()
        love.graphics.printf(tostring(introCD.n), -GAME_WIDTH * 0.5, -fh * 0.5, GAME_WIDTH, "center")
        love.graphics.pop()

        if not game.introHintFont then
            game.introHintFont = Mods.Font.new(14)
        end
        love.graphics.setColor(0.5, 0.5, 0.55, 0.85 * introCD.overlayFade)
        love.graphics.setFont(game.introHintFont)
        love.graphics.printf("ESC to cancel · Enemies ready", 0, GAME_HEIGHT * 0.88, GAME_WIDTH, "center")
    end

    -- Debug overlay (F1)
    if DEBUG then
        local es = player:getEffectiveStats()
        if not game.debugFont then
            game.debugFont = Mods.Font.new(11)
        end
        love.graphics.setFont(game.debugFont)
        local bulletDamage = es.bulletDamage or 0
        local damageMultiplier = es.damageMultiplier or 1
        local moveSpeed = es.moveSpeed or 0
        local bulletCount = es.bulletCount or 0
        local spreadAngle = es.spreadAngle or 0
        local ricochetCount = es.ricochetCount or 0
        local ricochetLabel = es.explosiveRounds and "0 (LOCKED)" or tostring(ricochetCount)
        local armor = es.armor or 0
        local lifestealOnKill = es.lifestealOnKill or 0
        local reloadSpeed = es.reloadSpeed or 0
        local cylinderSize = es.cylinderSize or 0
        local luck = es.luck or 0

        -- Stats panel (right side)
        local panelX = GAME_WIDTH - 260
        local py = 60
        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.rectangle("fill", panelX - 5, py - 5, 255, 240)
        love.graphics.setColor(0, 1, 0)
        love.graphics.print("-- EFFECTIVE STATS --", panelX, py)
        py = py + 16
        love.graphics.setColor(0.8, 1, 0.8)
        love.graphics.print(string.format("DMG: %.0f x%.2f  SPD: %.0f", bulletDamage, damageMultiplier, moveSpeed), panelX, py)
        py = py + 14
        love.graphics.print(string.format("Bullets: %d  Spread: %.2f", bulletCount, spreadAngle), panelX, py)
        py = py + 14
        love.graphics.print(string.format("Ricochet: %s  Explosive: %s", ricochetLabel, tostring(es.explosiveRounds)), panelX, py)
        py = py + 14
        love.graphics.print(string.format("Armor: %d  Lifesteal: %d", armor, lifestealOnKill), panelX, py)
        py = py + 14
        love.graphics.print(string.format("Reload: %.2fs  Cylinder: %d", reloadSpeed, cylinderSize), panelX, py)
        py = py + 14
        love.graphics.print(string.format("DeadEye: %s  Luck: %.2f", tostring(es.deadEye), luck), panelX, py)
        py = py + 20

        -- Perks list
        local dbgPerks = player.perks or {}
        love.graphics.setColor(0, 1, 0)
        love.graphics.print("-- PERKS (" .. #dbgPerks .. ") --", panelX, py)
        py = py + 16
        love.graphics.setColor(0.8, 1, 0.8)
        if #dbgPerks == 0 then
            love.graphics.print("(none)", panelX, py)
        else
            love.graphics.print(table.concat(dbgPerks, ", "), panelX, py)
        end
        py = py + 20

        -- Dev log: wide console to the left of the stat panel.
        local consoleX, consoleY, consoleW, consoleH = getDebugConsoleLayout()
        Mods.DevLog.drawConsole(consoleX, consoleY, consoleW, consoleH)
    end

    drawDevPanelOverlay()

    love.graphics.setColor(1, 1, 1)
end

return game
