local Gamestate = require("lib.hump.gamestate")
local Camera = require("lib.hump.camera")
local bump = require("lib.bump")

local Player = require("src.entities.player")
local Enemy  = require("src.entities.enemy")
local Pickup = require("src.entities.pickup")

local Combat = require("src.systems.combat")
local Progression = require("src.systems.progression")
local RoomManager = require("src.systems.room_manager")
local HUD    = require("src.ui.hud")
local DevLog = require("src.ui.devlog")
local DevPanel = require("src.ui.dev_panel")
local DamageNumbers = require("src.ui.damage_numbers")
local Font = require("src.ui.font")
local Cursor = require("src.ui.cursor")
local TextLayout = require("src.ui.text_layout")
local Settings = require("src.systems.settings")
local Keybinds = require("src.systems.keybinds")
local SettingsPanel = require("src.ui.settings_panel")
local TileRenderer = require("src.systems.tile_renderer")
local ImpactFX = require("src.systems.impact_fx")

local game = {}

local world
local camera
local player
local bullets
local enemies
local pickups
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
local pauseMenuView = "main" -- "main" | "settings"
local pauseSelectedIndex = 1
local pauseHoverIndex = nil
local pauseSettingsTab = "video"
local pauseSettingsHover = nil
local pauseSettingsBindCapture = nil -- action name while waiting for a key (Controls tab)
local characterSheetOpen = false
--- Set in update when death completes; next draw captures world → game over (see pendingGameOver block after camera:detach).
local pendingGameOver = nil
local devPanelOpen = false
local devPanelScroll = 0
local devPanelHover = nil
local devPanelRows = nil
--- Green bump AABB overlay (only when DEBUG); toggled from dev panel
local devShowHitboxes = true
-- After touching the exit while it's locked, keep off-screen enemy arrows until the room is clear
local offScreenEnemyHintActive = false

local function handleDebugAction(action)
    if not action or not player then return end
    if action == "debug_saloon" then
        local saloon = require("src.states.saloon")
        paused = false
        pauseMenuView = "main"
        pauseSelectedIndex = 1
        pauseHoverIndex = nil
        Gamestate.push(saloon, player, roomManager)
        DevLog.push("sys", "Debug: Entered saloon")
    elseif action == "debug_add_gold" then
        player.gold = player.gold + 10
        DevLog.push("sys", "Debug: +10 gold")
    elseif action == "debug_sub_gold" then
        player.gold = math.max(0, player.gold - 10)
        DevLog.push("sys", "Debug: -10 gold")
    end
end

-- Intro countdown (3→2→1) after menu: room + enemies loaded; gameplay frozen until done.
local introCountdownActive = false
local introCountdownN = 0
local introCountdownSegT = 0
local introCountdownOverlayFade = 0
local INTRO_COUNTDOWN_SEGMENT = 0.88
local INTRO_COUNTDOWN_OVERLAY_FADE_SEC = 0.42

local function pendingEnemiesIncoming()
    return currentRoom and currentRoom.pendingEnemySpawns and #currentRoom.pendingEnemySpawns > 0
end

local function roomHasLivingThreat()
    return #enemies > 0 or pendingEnemiesIncoming()
end

local function processPendingEnemySpawns(dt)
    if not currentRoom or not currentRoom.pendingEnemySpawns or not roomManager then return end
    local q = currentRoom.pendingEnemySpawns
    local i = 1
    while i <= #q do
        local e = q[i]
        e.time = e.time - dt
        if e.time <= 0 then
            local enemy = Enemy.new(e.type, e.x, e.y, roomManager.difficulty, { elite = e.elite })
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

local function refreshMouseAimOverride(pl, idleSec)
    local t = love.timer.getTime()
    if love.mouse.isDown(1) or love.mouse.isDown(2) then
        pl.mouseAimOverrideUntil = t + idleSec
    end
end

--- Aim point when not using mouse: horizontal line from player in move / last-facing direction.
local function keyboardFallbackAimPoint(pl)
    local cx = pl.x + pl.w * 0.5
    local cy = pl.y + pl.h * 0.5
    local ml = love.keyboard.isDown("a") or love.keyboard.isDown("left")
    local mr = love.keyboard.isDown("d") or love.keyboard.isDown("right")
    local dir
    if mr and not ml then
        dir = 1
    elseif ml and not mr then
        dir = -1
    else
        dir = pl.facingRight and 1 or -1
    end
    return cx + dir * 240, cy
end

local function drawAimCrosshair()
    if not player then return end
    if not Settings.getShowCrosshair() then return end
    -- Hide only in pure auto+keyboard mode; show again while mouse is active (even with auto on)
    if player.autoGun and player.keyboardAimMode then return end
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

-- Route the global debugLog used by combat.lua → DevLog combat category
function debugLog(msg)
    DevLog.push("combat", msg)
end

local function isOutOfBounds(entity, room)
    if not room then return false end
    return entity.y > room.height + 200
        or entity.y < -300
        or entity.x < -200
        or entity.x > room.width + 200
end

-- AABB overlap with padding (center-distance was too strict at tall doors / zoomed camera)
local DOOR_INTERACT_PAD = 10

-- Must be declared before any helper that reads it (Lua local scope starts at declaration)
local CAM_ZOOM = 2

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
    local viewW = GAME_WIDTH / CAM_ZOOM
    local viewH = GAME_HEIGHT / CAM_ZOOM
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
    local viewW = GAME_WIDTH / CAM_ZOOM
    local viewH = GAME_HEIGHT / CAM_ZOOM
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

local function tryExitThroughDoor()
    if transitionTimer > 0 or not isPlayerNearDoor() or not roomManager then
        return
    end
    roomManager:onRoomCleared()
    if roomManager:isCheckpoint() then
        local saloon = require("src.states.saloon")
        Gamestate.push(saloon, player, roomManager)
    else
        transitionTimer = 0.5
    end
end

local bgImage

-- Saloon door sprite (384×48, 8 frames of 48×48)
local doorSheet
local doorQuads = {}
local DOOR_FRAME_SIZE = 48
local DOOR_FRAMES = 8
local DOOR_FPS = 12

function game:init()
    bgImage = love.graphics.newImage("assets/backgrounds/forest.png")
    bgImage:setWrap("repeat", "clampzero")

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
        { id = "settings", label = "Settings" },
        { id = "restart", label = "Restart" },
        { id = "main_menu", label = "Main menu" },
    }
end

local function pauseMenuButtonLayout()
    local screenW, screenH = GAME_WIDTH, GAME_HEIGHT
    local bw, bh = 340, 48
    local gap = 10
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
    pauseMenuView = "main"
    pauseSettingsBindCapture = nil
    devPanelOpen = false
    devPanelScroll = 0
    devPanelHover = nil
    devShowHitboxes = true
    pendingGameOver = nil
    Gamestate.switch(game, { introCountdown = true })
end

local function pauseGoToMainMenu()
    paused = false
    pauseMenuView = "main"
    pauseSettingsBindCapture = nil
    devPanelOpen = false
    devPanelScroll = 0
    devPanelHover = nil
    pendingGameOver = nil
    local menu = require("src.states.menu")
    Gamestate.switch(menu)
end

local function drawCharacterSheet()
    if not player then return end
    local pad = 14
    local w, h = 300, 292
    local x, y = 18, 56
    love.graphics.setColor(0.08, 0.06, 0.05, 0.92)
    love.graphics.rectangle("fill", x, y, w, h, 8, 8)
    love.graphics.setColor(0.85, 0.65, 0.35, 0.9)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x, y, w, h, 8, 8)
    love.graphics.setLineWidth(1)
    if not game.charSheetTitleFont then
        game.charSheetTitleFont = Font.new(18)
    end
    if not game.charSheetBodyFont then
        game.charSheetBodyFont = Font.new(14)
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
    if #player.perks == 0 then
        love.graphics.setColor(0.55, 0.52, 0.48)
        love.graphics.print("(none yet)", x + pad, py)
        py = py + 20
    else
        love.graphics.setColor(0.78, 0.85, 0.72)
        local ptext = table.concat(player.perks, ", ")
        local tw = w - 2 * pad
        local _, lines = game.charSheetBodyFont:getWrap(ptext, tw)
        love.graphics.printf(ptext, x + pad, py, tw, "left")
        py = py + #lines * game.charSheetBodyFont:getHeight() + 8
    end
    love.graphics.setColor(0.88, 0.82, 0.72)
    local function gearLine(slot, label)
        local g = player.gear[slot]
        local name = g and g.name or "—"
        return string.format("%s: %s", label, name)
    end
    love.graphics.print(gearLine("hat", "Hat"), x + pad, py)
    py = py + 18
    love.graphics.print(gearLine("vest", "Vest"), x + pad, py)
    py = py + 18
    love.graphics.print(gearLine("boots", "Boots"), x + pad, py)
    py = py + 18
    love.graphics.print(gearLine("melee", "Melee"), x + pad, py)
    py = py + 18
    love.graphics.print(gearLine("shield", "Shield"), x + pad, py)
    py = py + 22
    love.graphics.setColor(0.45, 0.45, 0.48)
    local ck = Keybinds.formatActionKey("character")
    love.graphics.print(string.format("%s to close  ·  ESC", ck), x + pad, py)
end

local function devPerkById(pid)
    for _, p in ipairs(PerksData.pool) do
        if p.id == pid then return p end
    end
end

local function devPlayerHasPerk(pid)
    if not player then return true end
    for _, id in ipairs(player.perks) do
        if id == pid then return true end
    end
    return false
end

local function devClampScroll()
    if not devPanelRows then return end
    if not game.devPanelTitleFont then
        game.devPanelTitleFont = Font.new(16)
    end
    local ph = math.min(560, GAME_HEIGHT - 56)
    local maxS = DevPanel.maxScroll(devPanelRows, game.devPanelTitleFont, ph)
    devPanelScroll = math.max(0, math.min(maxS, devPanelScroll))
end

local function openDevPanel()
    if not DEBUG then return end
    devPanelOpen = true
    characterSheetOpen = false
    devPanelScroll = 0
    devPanelRows = DevPanel.buildRows(devShowHitboxes)
    if not game.devPanelTitleFont then
        game.devPanelTitleFont = Font.new(16)
    end
    devClampScroll()
end

local function devApplyAction(id)
    if not DEBUG or not player or not id then return end
    if id == "kill_player" then
        devPanelOpen = false
        characterSheetOpen = false
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
        devShowHitboxes = not devShowHitboxes
        devPanelRows = DevPanel.buildRows(devShowHitboxes)
        devClampScroll()
        DevLog.push("sys", "[dev] hitboxes " .. (devShowHitboxes and "on" or "off"))
    elseif id == "toggle_god" then
        player.devGodMode = not player.devGodMode
        DevLog.push("sys", "[dev] god mode " .. tostring(player.devGodMode))
    elseif id == "gold_100" then
        player:addGold(100)
        DevLog.push("sys", "[dev] +100 gold")
    elseif id == "gold_500" then
        player:addGold(500)
        DevLog.push("sys", "[dev] +500 gold")
    elseif id == "xp_50" then
        devPanelOpen = false
        characterSheetOpen = false
        if player:addXP(50) then
            local levelup = require("src.states.levelup")
            Gamestate.push(levelup, player, function() end)
        end
    elseif id == "xp_200" then
        devPanelOpen = false
        characterSheetOpen = false
        if player:addXP(200) then
            local levelup = require("src.states.levelup")
            Gamestate.push(levelup, player, function() end)
        end
    elseif id == "force_levelup" then
        devPanelOpen = false
        characterSheetOpen = false
        local levelup = require("src.states.levelup")
        Gamestate.push(levelup, player, function() end)
    elseif id == "open_door" then
        doorOpen = true
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
        if #enemies == 0 and not pendingEnemiesIncoming() and currentRoom then
            doorOpen = true
            if currentRoom.door then
                currentRoom.door.locked = false
            end
        end
        DevLog.push("sys", "[dev] cleared enemies")
    elseif id == "clear_bullets" then
        for i = #bullets, 1, -1 do
            local b = bullets[i]
            if world:hasItem(b) then world:remove(b) end
            table.remove(bullets, i)
        end
        DevLog.push("sys", "[dev] cleared bullets")
    elseif id == "spawn_bandit" or id == "spawn_gunslinger" or id == "spawn_buzzard" then
        local t = id == "spawn_bandit" and "bandit" or (id == "spawn_gunslinger" and "gunslinger" or "buzzard")
        local ex = player.x + (player.facingRight and 1 or -1) * 88
        local ey = player.y
        local e = Enemy.new(t, ex, ey, roomManager and roomManager.difficulty or 1, {})
        if e then
            world:add(e, e.x, e.y, e.w, e.h)
            table.insert(enemies, e)
            DevLog.push("sys", "[dev] spawn " .. t)
        end
    elseif id:sub(1, 5) == "perk:" then
        local pid = id:sub(6)
        if devPlayerHasPerk(pid) then
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

function game:enter(_, opts)
    introCountdownActive = false
    introCountdownN = 0
    introCountdownSegT = 0
    introCountdownOverlayFade = 0

    world = bump.newWorld(32)
    camera = Camera(400, 200)
    camera.scale = CAM_ZOOM
    player = Player.new(50, 300)
    player.autoGun = Settings.getDefaultAutoGun()
    world:add(player, player.x, player.y, player.w, player.h)
    player.isPlayer = true

    bullets = {}
    enemies = {}
    pickups = {}
    shakeTimer = 0
    shakeIntensity = 0
    gameTimer = 0
    doorOpen = false
    doorAnimFrame = 1
    doorAnimTimer = 0
    transitionTimer = 0
    paused = false
    pauseMenuView = "main"
    pauseSelectedIndex = 1
    pauseHoverIndex = nil
    pauseSettingsTab = "video"
    pauseSettingsHover = nil
    pauseSettingsBindCapture = nil
    characterSheetOpen = false
    pendingGameOver = nil
    devPanelOpen = false
    devPanelScroll = 0
    devPanelHover = nil
    devShowHitboxes = true
    devPanelRows = DevPanel.buildRows(devShowHitboxes)

    roomManager = RoomManager.new()
    roomManager:generateSequence()
    DevLog.init()
    DevLog.push("sys", "Run started")
    loadNextRoom()

    if opts and opts.introCountdown and Gamestate.current() == game then
        introCountdownActive = true
        introCountdownN = 3
        introCountdownSegT = 0
        introCountdownOverlayFade = 0
        if not game.introCountdownFont then
            game.introCountdownFont = Font.new(120)
        end
    end

    -- loadNextRoom may push saloon; only apply gameplay cursor if we're still the top state
    if Gamestate.current() == game then
        Cursor.setGameplay()
    end
end

function game:leave()
    Cursor.setDefault()
end

function loadNextRoom()
    DamageNumbers.clear()
    ImpactFX.clear()
    -- Remove every bump body (forward loop on a stale snapshot can skip items → broken transitions)
    while world:countItems() > 0 do
        local items, n = world:getItems()
        if n < 1 then break end
        world:remove(items[1])
    end
    bullets = {}
    pickups = {}
    enemies = {}
    doorOpen = false
    doorAnimFrame = 1
    doorAnimTimer = 0
    offScreenEnemyHintActive = false

    world:add(player, player.x, player.y, player.w, player.h)

    roomData = roomManager:nextRoom()
    if not roomData then
        -- Checkpoint reached
        local saloon = require("src.states.saloon")
        Gamestate.push(saloon, player, roomManager)
        return
    end

    currentRoom = roomManager:loadRoom(roomData, world, player)
    enemies = currentRoom.enemies
    DevLog.push("sys", string.format("Room %d/%d loaded  (diff %.1f)",
        roomManager.currentRoomIndex, #roomManager.roomSequence,
        roomManager.difficulty or 1))
end

function game:resume()
    Cursor.setGameplay()
    -- Returning from saloon -> load new cycle of rooms
    if roomManager.needsNewRooms then
        roomManager.needsNewRooms = false
        loadNextRoom()
    end
end

function game:update(dt)
    if paused then return end

    if devPanelOpen then
        if player and player.dying then
            devPanelOpen = false
        else
            return
        end
    end

    if introCountdownActive then
        processPendingEnemySpawns(dt)
        introCountdownOverlayFade = math.min(1, introCountdownOverlayFade + dt / INTRO_COUNTDOWN_OVERLAY_FADE_SEC)
        introCountdownSegT = introCountdownSegT + dt
        if introCountdownSegT >= INTRO_COUNTDOWN_SEGMENT then
            introCountdownSegT = 0
            introCountdownN = introCountdownN - 1
            if introCountdownN <= 0 then
                introCountdownActive = false
            end
        end
        if currentRoom and camera and player then
            local viewW = GAME_WIDTH / CAM_ZOOM
            local viewH = GAME_HEIGHT / CAM_ZOOM
            local px = player.x + player.w / 2
            local py = player.y + player.h / 2
            local cx = math.max(viewW / 2, math.min(currentRoom.width - viewW / 2, px))
            local cy = math.max(viewH / 2, math.min(currentRoom.height - viewH / 2, py))
            camera:lookAt(cx, cy)
        end
        return
    end

    gameTimer = gameTimer + dt


    -- Slow-mo from dead eye
    local timeMult = 1
    if player.deadEyeTimer > 0 then
        timeMult = 0.4
        dt = dt * timeMult
    end

    -- Shake
    if shakeTimer > 0 then
        shakeTimer = shakeTimer - dt
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
    local halfW = GAME_WIDTH / (2 * CAM_ZOOM)
    local halfH = GAME_HEIGHT / (2 * CAM_ZOOM)
    local viewL, viewT = camX - halfW, camY - halfH
    local viewR, viewB = camX + halfW, camY + halfH

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

        local aimIdle = Settings.getMouseAimIdleSec()
        refreshMouseAimOverride(player, aimIdle)
        local tNow = love.timer.getTime()
        mouseAimOn = tNow < (player.mouseAimOverrideUntil or 0)
        player.keyboardAimMode = not mouseAimOn
        autoTx, autoTy = Combat.findAutoTarget(enemies, player, world, viewL, viewT, viewR, viewB)
        if mouseAimOn then
            player.effectiveAimX, player.effectiveAimY = player.aimWorldX, player.aimWorldY
        elseif autoTx then
            player.effectiveAimX, player.effectiveAimY = autoTx, autoTy
        else
            player.effectiveAimX, player.effectiveAimY = keyboardFallbackAimPoint(player)
        end
    end

    -- Player update
    player:update(dt, world, enemies)

    if not player.dying then
    local i, leveledUp -- hoisted for goto (cannot jump over `local` in same block)
    -- Auto-fire only when findAutoTarget finds someone (on-screen + LOS). Mouse overrides *direction* to cursor, but never fires into empty space.
    if player.autoGun and not player.blocking and not player.reloading and player.shootCooldown <= 0 and player.ammo > 0 then
        local tx, ty
        if not autoTx then
            tx, ty = nil, nil
        elseif mouseAimOn then
            tx, ty = player.aimWorldX, player.aimWorldY
        else
            tx, ty = autoTx, autoTy
        end
        if tx then
            local bulletData = player:shoot(tx, ty)
            if bulletData then
                for _, data in ipairs(bulletData) do
                    local b = Combat.spawnBullet(world, data)
                    table.insert(bullets, b)
                end
                shakeTimer = 0.08
                shakeIntensity = 2
            end
        end
    end

    Combat.updateBullets(bullets, dt, world, enemies, player)
    if player.dying then goto skipLivingCombat end

    Combat.tryAutoMelee(player, enemies, world, viewL, viewT, viewR, viewB)
    Combat.checkPlayerMelee(player, enemies)

    -- Enemies update
    i = 1
    while i <= #enemies do
        local e = enemies[i]
        if e.alive then
            local bulletData = e:update(dt, world, player.x + player.w/2, player.y + player.h/2)
            if bulletData then
                local b = Combat.spawnBullet(world, bulletData)
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
            DevLog.push("combat", string.format("Killed %s  (xp+%d)", e.name or "enemy", e.xpValue or 0))
            local enemyDrops = Combat.onEnemyKilled(e, player)
            if enemyDrops then
                for _, drop in ipairs(enemyDrops) do
                    local p = Pickup.new(drop.x, drop.y, drop.type, drop.value)
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
    Combat.checkContactDamage(enemies, player)
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

    -- Check pickup collection
    leveledUp = Combat.checkPickups(pickups, player)

    -- Level up
    if leveledUp then
        DevLog.push("progress", "Level up → " .. player.level)
        local levelup = require("src.states.levelup")
        Gamestate.push(levelup, player, function() end)
    end

    -- Check if all enemies dead (and no staggered spawns left) -> open door
    if #enemies == 0 and not doorOpen and currentRoom and not pendingEnemiesIncoming() then
        doorOpen = true
        doorAnimFrame = 1
        doorAnimTimer = 0
        if currentRoom.door then
            currentRoom.door.locked = false
        end
        DevLog.push("sys", "All enemies cleared — door open")
    end

    -- Latch off-screen enemy hints: touch locked exit once, keep arrows until room clears
    if doorOpen or (#enemies == 0 and not pendingEnemiesIncoming()) then
        offScreenEnemyHintActive = false
    elseif currentRoom and currentRoom.door and not doorOpen and roomHasLivingThreat() and playerOverlapsDoorAABB() then
        offScreenEnemyHintActive = true
    end

    -- Exit door: use interact keybind when nearby (see tryExitThroughDoor)

    -- Kill plane (fell out of bounds)
    if isOutOfBounds(player, currentRoom) then
        player:beginDeath()
    end

    ::skipLivingCombat::
    end -- not player.dying

    DamageNumbers.update(dt)
    ImpactFX.update(dt)

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

    -- Player death (after collapse animation); snapshot taken in draw after world is rendered
    if player.dying and player.deathTimer >= Player.DEATH_DURATION then
        if not pendingGameOver then
            DevLog.push("sys", string.format("Player died  lv%d  %d rooms  $%d",
                player.level, roomManager.totalRoomsCleared, player.gold))
            pendingGameOver = {
                level = player.level,
                roomsCleared = roomManager.totalRoomsCleared,
                gold = player.gold,
                perksCount = #player.perks,
            }
        end
        return
    end

    -- Camera always follows player, clamped to room edges
    if currentRoom then
        local viewW = GAME_WIDTH / CAM_ZOOM
        local viewH = GAME_HEIGHT / CAM_ZOOM
        local px = player.x + player.w / 2
        local py = player.y + player.h / 2
        local cx = math.max(viewW / 2, math.min(currentRoom.width - viewW / 2, px))
        local cy = math.max(viewH / 2, math.min(currentRoom.height - viewH / 2, py))
        camera:lookAt(cx, cy)
    end
end

function game:keypressed(key)
    if introCountdownActive then
        if key == "f2" and DEBUG then
            openDevPanel()
            return
        end
        if key == "escape" then
            local menu = require("src.states.menu")
            Gamestate.switch(menu)
        end
        return
    end

    if DEBUG and devPanelOpen then
        if key == "escape" or key == "f2" then
            devPanelOpen = false
            devPanelHover = nil
        end
        return
    end

    if key == "f2" and DEBUG then
        openDevPanel()
        return
    end

    if player and player.dying then return end

    if paused and pauseMenuView == "settings" and pauseSettingsBindCapture then
        if key == "escape" then
            pauseSettingsBindCapture = nil
        else
            local normalized = Keybinds.normalizeCapturedKey(key)
            Settings.setKeybind(pauseSettingsBindCapture, normalized)
            Settings.save()
            pauseSettingsBindCapture = nil
        end
        return
    end

    if key == "escape" then
        if not paused and characterSheetOpen then
            characterSheetOpen = false
            return
        end
        if paused then
            if pauseMenuView == "settings" then
                pauseMenuView = "main"
                pauseSettingsBindCapture = nil
            else
                paused = false
                pauseMenuView = "main"
            end
        else
            paused = true
            pauseMenuView = "main"
            pauseSelectedIndex = 1
            pauseHoverIndex = nil
        end
        return
    end

    if paused then
        if pauseMenuView == "settings" then
            if key == "backspace" then
                pauseMenuView = "main"
                pauseSettingsBindCapture = nil
            elseif key == "[" then
                pauseSettingsTab = SettingsPanel.cycleTab(pauseSettingsTab, -1)
            elseif key == "]" then
                pauseSettingsTab = SettingsPanel.cycleTab(pauseSettingsTab, 1)
            end
            return
        end
        local list = pauseMenuEntries()
        if key == "up" or key == "w" then
            pauseSelectedIndex = pauseSelectedIndex - 1
            if pauseSelectedIndex < 1 then pauseSelectedIndex = #list end
        elseif key == "down" or key == "s" then
            pauseSelectedIndex = pauseSelectedIndex + 1
            if pauseSelectedIndex > #list then pauseSelectedIndex = 1 end
        elseif key == "return" or key == "space" or key == "kpenter" then
            local id = list[pauseSelectedIndex].id
            if id == "resume" then
                paused = false
                pauseMenuView = "main"
            elseif id == "settings" then
                pauseMenuView = "settings"
            elseif id == "restart" then
                pauseRestartRun()
            elseif id == "main_menu" then
                pauseGoToMainMenu()
            end
        end
        return
    end

    if Keybinds.matches("character", key) then
        characterSheetOpen = not characterSheetOpen
        return
    end
    if Keybinds.matches("ult", key) then
        player:tryActivateUlt()
        return
    end

    if Keybinds.matches("jump", key) or key == "w" or key == "up" then
        player:jump()
    end
    if Keybinds.matches("dash", key) then
        player:tryDash()
    end
    if Keybinds.matches("drop", key) or key == "down" then
        player:tryDropThrough()
    end
    if Keybinds.matches("reload", key) then
        player:reload()
    end
    if Keybinds.matches("melee", key) then
        player:meleeAttack()
    end
    if key == "h" then
        player:spinHolster()
    end
    if key == "e" then
        tryExitThroughDoor()
    end
end

function game:mousemoved(x, y, dx, dy)
    local gx, gy = windowToGame(x, y)
    if DEBUG and devPanelOpen and devPanelRows then
        if not game.devPanelTitleFont then
            game.devPanelTitleFont = Font.new(16)
        end
        local px, py = 12, 44
        local pw = 308
        local ph = math.min(560, GAME_HEIGHT - 56)
        devPanelHover = DevPanel.hitTest(devPanelRows, gx, gy, devPanelScroll, px, py, pw, ph, game.devPanelTitleFont)
        return
    end
    if introCountdownActive then return end
    if player and player.dying then return end
    if paused then
        pauseHoverIndex = nil
        if pauseMenuView == "main" then
            for i, r in ipairs(pauseMenuButtonLayout()) do
                if pauseHitRect(gx, gy, r) then
                    pauseHoverIndex = i
                    pauseSelectedIndex = i
                    break
                end
            end
        else
            if not game.pauseMenuButtonFont then
                game.pauseMenuButtonFont = Font.new(22)
            end
            local h = SettingsPanel.hitTest(GAME_WIDTH, GAME_HEIGHT, pauseSettingsTab, gx, gy, game.pauseMenuButtonFont)
            if h then
                if h.kind == "tab" then
                    pauseSettingsHover = { kind = "tab", id = h.id }
                elseif h.kind == "back" then
                    pauseSettingsHover = { kind = "back" }
                elseif h.kind == "row" then
                    pauseSettingsHover = { kind = "row", index = h.index }
                elseif h.kind == "slider" then
                    pauseSettingsHover = { kind = "slider", index = h.index, key = h.key }
                end
            else
                pauseSettingsHover = nil
            end
        end
        return
    end
    if not player then return end
    if math.abs(dx) + math.abs(dy) > 0.25 then
        player.mouseAimOverrideUntil = love.timer.getTime() + Settings.getMouseAimIdleSec()
    end
end

function game:mousepressed(x, y, button)
    local gx, gy = windowToGame(x, y)
    if DEBUG and devPanelOpen and devPanelRows and button == 1 then
        if not game.devPanelTitleFont then
            game.devPanelTitleFont = Font.new(16)
        end
        local px, py = 12, 44
        local pw = 308
        local ph = math.min(560, GAME_HEIGHT - 56)
        local hit = DevPanel.hitTest(devPanelRows, gx, gy, devPanelScroll, px, py, pw, ph, game.devPanelTitleFont)
        if hit then
            devApplyAction(hit)
        end
        return
    end
    if introCountdownActive then return end
    if player and player.dying then return end
    if paused then
        if button ~= 1 then return end
        if pauseMenuView == "main" then
            for _, r in ipairs(pauseMenuButtonLayout()) do
                if pauseHitRect(gx, gy, r) then
                    if r.id == "resume" then
                        paused = false
                        pauseMenuView = "main"
                    elseif r.id == "settings" then
                        pauseMenuView = "settings"
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
                game.pauseMenuButtonFont = Font.new(22)
            end
            local h = SettingsPanel.hitTest(GAME_WIDTH, GAME_HEIGHT, pauseSettingsTab, gx, gy, game.pauseMenuButtonFont)
            local r = SettingsPanel.applyHit(h, player)
            if r then
                if r.setTab then pauseSettingsTab = r.setTab end
                if r.goBack then pauseMenuView = "main" end
                if r.action then handleDebugAction(r.action) end
            end
        end
        return
    end
    if player then
        player.mouseAimOverrideUntil = love.timer.getTime() + Settings.getMouseAimIdleSec()
    end
    if button == 1 and player and not player.blocking then
        -- Manual shot at cursor; player:shoot cooldown blocks double-tap with auto-fire in update
        local mx, my = camera:worldCoords(gx, gy, 0, 0, GAME_WIDTH, GAME_HEIGHT)
        local bulletData = player:shoot(mx, my)
        if bulletData then
            for _, data in ipairs(bulletData) do
                local b = Combat.spawnBullet(world, data)
                table.insert(bullets, b)
            end
            shakeTimer = 0.08
            shakeIntensity = 2
        end
    end
    if button == 2 then
        local slot = HUD.hitLoadout(gx, gy, GAME_HEIGHT)
        if slot == "gun" then
            player.autoGun = not player.autoGun
        elseif slot == "melee" then
            player.autoMelee = not player.autoMelee
        elseif slot == "shield" and player:shieldAllowsAutoBlock() then
            player.autoBlock = not player.autoBlock
        else
            player:reload()
        end
    end
end

function game:wheelmoved(x, y)
    if not DEBUG or not devPanelOpen then return end
    devPanelScroll = devPanelScroll - y * 36
    devClampScroll()
end

function game:draw()
    -- Camera with shake
    local sx, sy = 0, 0
    if shakeTimer > 0 then
        local sk = Settings.getScreenShakeScale()
        sx = (math.random() - 0.5) * shakeIntensity * 2 * sk
        sy = (math.random() - 0.5) * shakeIntensity * 2 * sk
    end

    camera:attach(0, 0, GAME_WIDTH, GAME_HEIGHT)
    love.graphics.translate(sx, sy)

    -- Room background
    if currentRoom then
        local camX, camY = camera:position()

        -- Parallax background — tiles horizontally, scrolls at 30% of camera speed
        local viewW = GAME_WIDTH / CAM_ZOOM
        local viewH = GAME_HEIGHT / CAM_ZOOM
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

        -- Walls (left, right, ceiling)
        for _, wall in ipairs(currentRoom.walls) do
            TileRenderer.drawWall(wall.x, wall.y, wall.w, wall.h)
        end

        -- Platforms
        for _, plat in ipairs(currentRoom.platforms) do
            if plat.h >= 32 then
                TileRenderer.drawWall(plat.x, plat.y, plat.w, plat.h)
            else
                TileRenderer.drawPlatform(plat.x, plat.y, plat.w, plat.h)
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

            if not doorOpen and roomHasLivingThreat() then
                love.graphics.setColor(1, 0.85, 0.35, 0.75)
                love.graphics.printf("Locked", door.x - 16, door.y - 18, door.w + 32, "center")
            end

            if doorOpen then
                love.graphics.setColor(1, 1, 1, 0.85)
                if player and isPlayerNearDoor() then
                    local ik = Keybinds.formatActionKey("interact")
                    love.graphics.printf(string.format("[%s] Exit", ik), door.x - 24, door.y - 20, door.w + 48, "center")
                else
                    love.graphics.printf("Exit", door.x - 10, door.y - 18, door.w + 20, "center")
                end
            end
        end
    end

    -- Pickups
    for _, p in ipairs(pickups) do
        p:draw()
    end

    -- Enemies
    for _, e in ipairs(enemies) do
        e:draw()
    end

    -- Player
    player:draw()
    if not introCountdownActive then
        drawAimCrosshair()
    end

    -- Bullets
    for _, b in ipairs(bullets) do
        b:draw()
    end

    ImpactFX.draw()
    DamageNumbers.draw()

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

    if pendingGameOver then
        local c = love.graphics.getCanvas()
        local snapshot = nil
        if c then
            local ok, id = pcall(function() return c:newImageData() end)
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
            backgroundImage = snapshot,
        }
        pendingGameOver = nil
        local gameover = require("src.states.gameover")
        Gamestate.switch(gameover, args)
        local cur = Gamestate.current()
        if cur and cur.draw then
            cur:draw(cur)
        end
        return
    end

    if not introCountdownActive then
        -- Near locked exit + surviving enemies off-screen: blink arrows on viewport edge (screen space)
        drawExitBlockedOffscreenArrows()
        drawExitArrow()

        -- HUD (screen space)
        HUD.draw(player)
        DevLog.drawOverlay(GAME_WIDTH, GAME_HEIGHT)
        if roomManager then
            HUD.drawRoomInfo(roomManager.currentRoomIndex, #roomManager.roomSequence)
        end

        -- Transition fade
        if transitionTimer > 0 then
            local alpha = 1 - (transitionTimer / 0.5)
            love.graphics.setColor(0, 0, 0, alpha)
            love.graphics.rectangle("fill", 0, 0, GAME_WIDTH, GAME_HEIGHT)
        end

        HUD.drawDeadEye(player)

        if characterSheetOpen and not paused then
            love.graphics.setColor(0, 0, 0, 0.35)
            love.graphics.rectangle("fill", 0, 0, GAME_WIDTH, GAME_HEIGHT)
            drawCharacterSheet()
        end

        if paused then
            love.graphics.setColor(0, 0, 0, 0.48)
            love.graphics.rectangle("fill", 0, 0, GAME_WIDTH, GAME_HEIGHT)

            if not game.pauseTitleFont then
                game.pauseTitleFont = Font.new(32)
            end
            if not game.pauseMenuButtonFont then
                game.pauseMenuButtonFont = Font.new(22)
            end
            if not game.pauseHintFont then
                game.pauseHintFont = Font.new(15)
            end
            if not game.pauseSettingsBodyFont then
                game.pauseSettingsBodyFont = Font.new(16)
            end

            if pauseMenuView == "main" then
                love.graphics.setFont(game.pauseTitleFont)
                love.graphics.setColor(1, 0.86, 0.28, 0.95)
                love.graphics.printf("PAUSED", 0, GAME_HEIGHT * 0.16, GAME_WIDTH, "center")

                local rects = pauseMenuButtonLayout()
                for i, r in ipairs(rects) do
                    local hover = (pauseHoverIndex == i) or (pauseHoverIndex == nil and pauseSelectedIndex == i)
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
                        TextLayout.printfYCenteredInRect(game.pauseMenuButtonFont, r.y, r.h),
                        r.w,
                        "center"
                    )
                end

                love.graphics.setFont(game.pauseHintFont)
                love.graphics.setColor(0.45, 0.45, 0.48)
                love.graphics.printf("Arrows / mouse  ·  Enter  ·  ESC to resume", 0, GAME_HEIGHT * 0.88, GAME_WIDTH, "center")
            else
                SettingsPanel.draw(GAME_WIDTH, GAME_HEIGHT, pauseSettingsTab, {
                    title = game.pauseTitleFont,
                    tab = game.pauseMenuButtonFont,
                    row = game.pauseSettingsBodyFont,
                    hint = game.pauseHintFont,
                }, pauseSettingsHover, pauseSettingsBindCapture)
            end
        end
    else
        love.graphics.setColor(0.02, 0.02, 0.04, 0.52 + (0.74 - 0.52) * introCountdownOverlayFade)
        love.graphics.rectangle("fill", 0, 0, GAME_WIDTH, GAME_HEIGHT)

        local sc, a = introCountdownDigitStyle(introCountdownSegT)
        love.graphics.push()
        love.graphics.translate(GAME_WIDTH * 0.5, GAME_HEIGHT * 0.48)
        love.graphics.scale(sc)
        love.graphics.setColor(1, 0.86, 0.28, a)
        love.graphics.setFont(game.introCountdownFont)
        local fh = game.introCountdownFont:getHeight()
        love.graphics.printf(tostring(introCountdownN), -GAME_WIDTH * 0.5, -fh * 0.5, GAME_WIDTH, "center")
        love.graphics.pop()

        if not game.introHintFont then
            game.introHintFont = Font.new(14)
        end
        love.graphics.setColor(0.5, 0.5, 0.55, 0.85 * introCountdownOverlayFade)
        love.graphics.setFont(game.introHintFont)
        love.graphics.printf("ESC to cancel · Enemies ready", 0, GAME_HEIGHT * 0.88, GAME_WIDTH, "center")
    end

    -- Debug overlay (F1)
    if DEBUG then
        local es = player:getEffectiveStats()
        if not game.debugFont then
            game.debugFont = Font.new(11)
        end
        love.graphics.setFont(game.debugFont)

        -- Stats panel (right side)
        local panelX = GAME_WIDTH - 260
        local py = 60
        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.rectangle("fill", panelX - 5, py - 5, 255, 240)
        love.graphics.setColor(0, 1, 0)
        love.graphics.print("-- EFFECTIVE STATS --", panelX, py)
        py = py + 16
        love.graphics.setColor(0.8, 1, 0.8)
        love.graphics.print(string.format("DMG: %.0f x%.2f  SPD: %.0f", es.bulletDamage, es.damageMultiplier, es.moveSpeed), panelX, py)
        py = py + 14
        love.graphics.print(string.format("Bullets: %d  Spread: %.2f", es.bulletCount, es.spreadAngle), panelX, py)
        py = py + 14
        love.graphics.print(string.format("Ricochet: %d  Explosive: %s", es.ricochetCount, tostring(es.explosiveRounds)), panelX, py)
        py = py + 14
        love.graphics.print(string.format("Armor: %d  Lifesteal: %d", es.armor, es.lifestealOnKill), panelX, py)
        py = py + 14
        love.graphics.print(string.format("Reload: %.2fs  Cylinder: %d", es.reloadSpeed, es.cylinderSize), panelX, py)
        py = py + 14
        love.graphics.print(string.format("DeadEye: %s  Luck: %.2f", tostring(es.deadEye), es.luck), panelX, py)
        py = py + 20

        -- Perks list
        love.graphics.setColor(0, 1, 0)
        love.graphics.print("-- PERKS (" .. #player.perks .. ") --", panelX, py)
        py = py + 16
        love.graphics.setColor(0.8, 1, 0.8)
        if #player.perks == 0 then
            love.graphics.print("(none)", panelX, py)
        else
            love.graphics.print(table.concat(player.perks, ", "), panelX, py)
        end
        py = py + 20

        -- Dev log
        DevLog.draw(panelX, py, 250)
    end

    if DEBUG and devPanelOpen and devPanelRows and player then
        love.graphics.setColor(0, 0, 0, 0.38)
        love.graphics.rectangle("fill", 0, 0, GAME_WIDTH, GAME_HEIGHT)
        if not game.devPanelTitleFont then
            game.devPanelTitleFont = Font.new(16)
        end
        if not game.devPanelRowFont then
            game.devPanelRowFont = Font.new(13)
        end
        devClampScroll()
        local px, py = 12, 44
        local pw = 308
        local ph = math.min(560, GAME_HEIGHT - 56)
        DevPanel.draw(devPanelRows, devPanelScroll, px, py, pw, ph, devPanelHover, {
            title = game.devPanelTitleFont,
            row = game.devPanelRowFont,
        })
        love.graphics.setFont(game.devPanelRowFont)
        love.graphics.setColor(0.55, 0.55, 0.58)
        love.graphics.printf("F2 / ESC close  ·  wheel scroll", px, math.min(py + ph + 6, GAME_HEIGHT - 20), pw, "center")
    end

    love.graphics.setColor(1, 1, 1)
end

return game
