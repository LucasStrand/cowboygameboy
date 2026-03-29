-- Single `Mods` table for requires: LuaJIT 60-upvalue closure limit (saloon:enter / callbacks).
local Mods = {
    Gamestate = require("lib.hump.gamestate"),
    Camera = require("lib.hump.camera"),
    bump = require("lib.bump"),
    Font = require("src.ui.font"),
    Blackjack = require("src.systems.blackjack"),
    Roulette = require("src.systems.roulette"),
    Slots = require("src.systems.slots"),
    Shop = require("src.systems.shop"),
    PerkCard = require("src.ui.perk_card"),
    Cursor = require("src.ui.cursor"),
    Keybinds = require("src.systems.keybinds"),
    ContentTooltips = require("src.systems.content_tooltips"),
    NPC = require("src.entities.npc"),
    Pickup = require("src.entities.pickup"),
    Combat = require("src.systems.combat"),
    DamageNumbers = require("src.ui.damage_numbers"),
    DevLog = require("src.ui.devlog"),
    DevPanel = require("src.ui.dev_panel"),
    TextLayout = require("src.ui.text_layout"),
    Settings = require("src.systems.settings"),
    SettingsPanel = require("src.ui.settings_panel"),
    Progression = require("src.systems.progression"),
    Sfx = require("src.systems.sfx"),
    Buffs = require("src.systems.buffs"),
    HUD = require("src.ui.hud"),
    MusicDirector = require("src.systems.music_director"),
    Perks = require("src.data.perks"),
    GameRng = require("src.systems.game_rng"),
    GoldCoin = require("src.data.gold_coin"),
    ImpactFX = require("src.systems.impact_fx"),
    saloonRoom = require("src.data.saloon_room"),
    WorldInteractLabelBatch = require("src.ui.world_interact_label_batch"),
}

local WeaponsData = require("src.data.weapons")

local saloon = {}

-- Persistent assets (loaded once)
local bgImage = nil
local doorSheet = nil
local doorQuads = {}
local DOOR_FRAME_SIZE = 48

-- Bar decoration sprites (loaded once)
local decor = {}
local rouletteTableQuad = nil
local slotMachineQuad = nil
-- Pixel Interior LRK — decorations sheet (floor lamp + plants share one atlas)
local pixelInteriorDecorImg = nil
local pixelDecorQuads = {}
local pixelDecorSizes = {} -- [name] = { w, h } in source pixels
local pixelInteriorCabinetImg = nil
local pixelCabinetQuads = {}
local pixelCabinetSizes = {} -- [name] = { w, h } in source pixels
-- Glow Y: old `bsmtFloorY - qh*s*0.68` sat ~32% down the frame; LRK shade centroid is ~9px below quad top
local BASEMENT_FLOOR_LAMP_GLOW_FROM_TOP_PX = { floor_lamp = 9, floor_lamp_b = 9, floor_lamp_c = 9 }

-- Per-visit state
local player = nil
local roomManager = nil
local world = nil
local camera = nil
local npcs = {}
local platforms = {}
local walls = {}
local exitDoor = nil
local testDoor = nil
local difficulty = 1

local mode = "walking"  -- walking | blackjack | roulette | slots | casino_menu | shop | perk_selection
local blackjackGame = nil
local rouletteGame = nil
local slotsGame = nil
local casinoMenuRects = {}
local shop = nil
local message = ""
local messageTimer = 0
local perkOptions = nil
local hoveredPerk = nil
local fonts = {}

-- Wanted quest stub (foreground pillar)
local wantedQuestStage = "available" -- available | pending (marker hidden; quest UI later)
local wantedPoster = {
    x = 0, y = 0, cx = 0,
    markerY = 0,
    interactY = 0,
    s = 0.30,
    r2 = 62 * 62, -- interact radius squared (includes some vertical forgiveness)
}

local CAM_ZOOM = 3

-- Camera + misc state packed to avoid upvalue limit
local cam = {
    lerpSpeed = 5,
    lookAheadX = 60, lookAheadY = 30, groundedY = -15,
    targetX = 0, targetY = 0,
    currentX = 0, currentY = 0,
}

-- Monster Energy on the bar counter
local monster = { img = nil, drunk = false, x = 0, y = 0 }

-- All new saloon depth/atmosphere helpers packed into one table (upvalue budget)
local Atmos = {
    dustMotes = {},
    DUST_COUNT = 20,
}

-- bar.png native size; scale lives in `saloon_room.decor.barCounterScale`
local BAR_COUNTER_IMG_W, BAR_COUNTER_IMG_H = 127, 47
local MONSTER_CAN_SCALE = 0.4

local function saloonBarGeometry(floorY)
    local L = Mods.saloonRoom.decor
    local scale = (L and L.barCounterScale) or 0.52
    local segments = (L and L.barCounterSegments) or 2
    if segments < 1 then segments = 1 end
    local barW = BAR_COUNTER_IMG_W * scale
    local barH = BAR_COUNTER_IMG_H * scale
    local barY = floorY - barH
    local totalBarW = barW * segments
    return scale, barW, barH, barY, totalBarW, segments
end

-- bar.png: light countertop is rows 0–2; mug bases sit on the surface at ~row 3 (see bar asset)
local function saloonBarCounterSurfaceY(barY, barScale)
    return barY + 3 * barScale
end

local nearbyNPC = nil  -- NPC currently in interact range
local pickups = {}
local bullets = {}

-- Pause / debug (parity with game state — Esc pause, F2 dev panel, F1 stats when DEBUG)
local paused = false
local pauseMenuView = "main"
local pauseSelectedIndex = 1
local pauseHoverIndex = nil
local pauseSettingsTab = "video"
local pauseSettingsHover = nil
local pauseSettingsBindCapture = nil
local pauseSettingsSliderDragKey = nil
local characterSheetOpen = false

--- Same pointer path as `game:tryPrimaryMeleeTapFromPointer` (LMB + melee key).
local function tryPrimaryMeleeTapFromPointer(fromMeleeKey)
    if not player or not camera or player.blocking or characterSheetOpen then return end
    local mx, my = love.mouse.getPosition()
    local gx, gy = windowToGame(mx, my)
    player:tryMeleePrimaryMouseTap(camera, gx, gy, GAME_WIDTH, GAME_HEIGHT, {
        fromMeleeKey = fromMeleeKey == true,
    })
end

local devPanelOpen = false
local devPanelScroll = 0
local devPanelHover = nil
local devPanelRows = nil
local devPanelRowsFull = nil
local devPanelSearchQuery = ""
local devPanelSearchFocus = false
local devPanelPauseGameplay = true
local devShowHitboxes = true

local function devToolsEnabled()
    return DEBUG or DEV_TOOLS_ENABLED
end

---------------------------------------------------------------------------
-- Pause menu + dev (saloon context)
---------------------------------------------------------------------------
local function pauseMenuEntries()
    return {
        { id = "resume", label = "Resume" },
        { id = "settings", label = "Settings" },
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
    pauseMenuView = "main"
    pauseSettingsBindCapture = nil
    pauseSettingsSliderDragKey = nil
    devPanelOpen = false
    devPanelScroll = 0
    devPanelHover = nil
    devPanelPauseGameplay = true
    devShowHitboxes = true
    characterSheetOpen = false
    local game = require("src.states.game")
    Mods.Gamestate.switch(game, { introCountdown = true })
end

local function pauseGoToMainMenu()
    paused = false
    pauseMenuView = "main"
    pauseSettingsBindCapture = nil
    pauseSettingsSliderDragKey = nil
    devPanelOpen = false
    devPanelScroll = 0
    devPanelHover = nil
    devPanelPauseGameplay = true
    characterSheetOpen = false
    local menu = require("src.states.menu")
    Mods.Gamestate.switch(menu)
end

local function devPerkById(pid)
    for _, p in ipairs(Mods.Perks.pool) do
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

local function pointInRect(x, y, rx, ry, rw, rh)
    return x >= rx and x <= rx + rw and y >= ry and y <= ry + rh
end

local function getDevPanelLayout()
    return Mods.DevPanel.panelRect(GAME_WIDTH, GAME_HEIGHT)
end

local function getDebugConsoleLayout()
    local panelX = GAME_WIDTH - 260
    local consoleGap = 12
    local consoleH = 240
    local consoleW = math.min(720, math.max(420, panelX - 24))
    local consoleX = math.max(12, panelX - consoleW - consoleGap)
    return consoleX, 60, consoleW, consoleH
end

local function devClampScroll()
    if not devPanelRows then return end
    if not saloon.devPanelTitleFont then
        saloon.devPanelTitleFont = Mods.Font.new(16)
    end
    if not saloon.devPanelRowFont then
        saloon.devPanelRowFont = Mods.Font.new(13)
    end
    local _, _, pw, ph = getDevPanelLayout()
    local maxS = Mods.DevPanel.maxScroll(devPanelRows, saloon.devPanelTitleFont, saloon.devPanelRowFont, pw, ph)
    devPanelScroll = math.max(0, math.min(maxS, devPanelScroll))
end

local function saloonDevApplySearchFilter()
    if not devPanelRowsFull then return end
    devPanelRows = Mods.DevPanel.filterRows(devPanelRowsFull, devPanelSearchQuery or "")
    devClampScroll()
end

local function saloonDevRebuildRows()
    devPanelRowsFull = Mods.DevPanel.buildRows({
        gameplayPaused = devPanelPauseGameplay,
        showHitboxes = devShowHitboxes,
    })
    devPanelRows = Mods.DevPanel.filterRows(devPanelRowsFull, devPanelSearchQuery or "")
    devClampScroll()
end

local function openDevPanel()
    if not devToolsEnabled() then return end
    devPanelOpen = true
    devPanelPauseGameplay = true
    characterSheetOpen = false
    devPanelScroll = 0
    devPanelHover = nil
    devPanelSearchQuery = ""
    devPanelSearchFocus = false
    saloonDevRebuildRows()
    if not saloon.devPanelTitleFont then
        saloon.devPanelTitleFont = Mods.Font.new(16)
    end
    if not saloon.devPanelRowFont then
        saloon.devPanelRowFont = Mods.Font.new(13)
    end
end

--- Gold from casino wins — scattered around the player so you walk to collect (lighter pop than dev cheat).
local function spawnSaloonGoldDrops(amount)
    if not amount or amount <= 0 or not world or not player then return end
    local specs, overflow = Mods.GoldCoin.pickupSpecsForTotal(amount, 28)
    if overflow > 0 then
        player:addGold(overflow, "casino_payout_overflow")
    end
    if #specs < 1 then return end
    local pw = 10
    local cx = player.x + player.w / 2
    local roomW = Mods.saloonRoom.width
    local n = #specs
    for i = 1, n do
        local sp = specs[i]
        -- Ring around the player (not underfoot): ~56–112 px so you move to grab them
        local ang = (i / n) * math.pi * 2 + (Mods.GameRng.randomFloat("saloon.payout.ang", 0, 1) - 0.5) * 0.45
        local dist = 56 + Mods.GameRng.randomFloat("saloon.payout.dist", 0, 56)
        local px = cx - pw / 2 + math.cos(ang) * dist + (Mods.GameRng.randomFloat("saloon.payout.px", 0, 1) - 0.5) * 10
        px = math.max(4, math.min(roomW - pw - 4, px))
        local py = player.y - 5 - Mods.GameRng.randomFloat("saloon.payout.py", 0, 10)
        local p = Mods.Pickup.new(px, py, sp.type, sp.value)
        p.casinoPayout = true
        p.vy = -70 - Mods.GameRng.randomFloat("saloon.payout.vy", 0, 55)
        p.vx = (Mods.GameRng.randomFloat("saloon.payout.vx", 0, 1) - 0.5) * 36
        world:add(p, p.x, p.y, p.w, p.h)
        table.insert(pickups, p)
    end
end

local function tryFlushCasinoGoldToFloor()
    if mode ~= "walking" or not world or not player then return end
    if blackjackGame and blackjackGame.pendingFloorGold and blackjackGame.pendingFloorGold > 0 then
        local a = blackjackGame.pendingFloorGold
        blackjackGame.pendingFloorGold = nil
        spawnSaloonGoldDrops(a)
    end
    if rouletteGame and rouletteGame.pendingFloorGold and rouletteGame.pendingFloorGold > 0 then
        local a = rouletteGame.pendingFloorGold
        rouletteGame.pendingFloorGold = nil
        spawnSaloonGoldDrops(a)
    end
    if slotsGame and slotsGame.pendingFloorGold and slotsGame.pendingFloorGold > 0 then
        local a = slotsGame.pendingFloorGold
        slotsGame.pendingFloorGold = nil
        spawnSaloonGoldDrops(a)
    end
end

--- Settings panel debug rows (gameplay tab): saloon-safe actions
local function saloonSettingsDebugAction(action)
    if not action or not player then return end
    if action == "debug_saloon" then
        Mods.DevLog.push("sys", "Already in the saloon.")
    elseif action == "debug_add_gold" then
        spawnSaloonGoldDrops(10)
        Mods.DevLog.push("sys", "Debug: +10 gold (drops)")
    elseif action == "debug_sub_gold" then
        player:spendGold(10, "dev_sub_gold")
        Mods.DevLog.push("sys", "Debug: -10 gold")
    elseif action == "fake_session" then
        Mods.DevLog.push("sys", "Fake session: use from main menu.")
    end
end

local function saloonDevApplyAction(id)
    if not devToolsEnabled() or not player or not id then return end
    if id == Mods.DevPanel.HIT_SEARCH then return end
    if id == "toggle_dev_pause" then
        devPanelPauseGameplay = not (devPanelPauseGameplay ~= false)
        saloonDevRebuildRows()
        Mods.DevLog.push("sys", "[dev] gameplay " .. ((devPanelPauseGameplay ~= false) and "paused" or "live"))
        return
    end
    if id == "kill_player" then
        devPanelOpen = false
        characterSheetOpen = false
        Mods.DevLog.push("sys", "[dev] kill player — N/A in saloon (resume run first)")
    elseif id == "full_heal" then
        player.hp = player:getEffectiveStats().maxHP
        Mods.DevLog.push("sys", "[dev] full heal")
    elseif id == "hurt_1" then
        if not player.devGodMode then
            player.hp = math.max(1, player.hp - 1)
        end
        Mods.DevLog.push("sys", "[dev] hurt 1")
    elseif id == "toggle_hitboxes" then
        devShowHitboxes = not devShowHitboxes
        saloonDevRebuildRows()
        Mods.DevLog.push("sys", "[dev] hitboxes " .. (devShowHitboxes and "on" or "off"))
    elseif id == "toggle_god" then
        player.devGodMode = not player.devGodMode
        Mods.DevLog.push("sys", "[dev] god mode " .. tostring(player.devGodMode))
    elseif id == "ult_full" then
        player.ultCharge = 1
        Mods.DevLog.push("sys", "[dev] ult charge full")
    elseif id == "gold_100" then
        spawnSaloonGoldDrops(100)
        Mods.DevLog.push("sys", "[dev] +100 gold (drops)")
    elseif id == "gold_500" then
        spawnSaloonGoldDrops(500)
        Mods.DevLog.push("sys", "[dev] +500 gold (drops)")
    elseif id == "xp_50" then
        devPanelOpen = false
        characterSheetOpen = false
        if player:addXP(50) then
            local levelup = require("src.states.levelup")
            Mods.Gamestate.push(levelup, player, function() end)
        end
    elseif id == "xp_200" then
        devPanelOpen = false
        characterSheetOpen = false
        if player:addXP(200) then
            local levelup = require("src.states.levelup")
            Mods.Gamestate.push(levelup, player, function() end)
        end
    elseif id == "force_levelup" then
        devPanelOpen = false
        characterSheetOpen = false
        local levelup = require("src.states.levelup")
        Mods.Gamestate.push(levelup, player, function() end)
    elseif id == "open_door" or id == "clear_enemies" or id == "clear_bullets"
        or id == "spawn_bandit" or id == "spawn_gunslinger" or id == "spawn_buzzard" then
        Mods.DevLog.push("sys", "[dev] " .. id .. " — N/A in saloon (resume run for room tools)")
    elseif id:sub(1, 4) == "gun:" then
        local gunId = id:sub(5)
        local Guns = require("src.data.guns")
        local gunDef = Guns.getById(gunId)
        if gunDef then
            local slot = player.activeWeaponSlot
            player:equipWeapon(gunDef, slot)
            Mods.DevLog.push("sys", "[dev] equipped " .. gunDef.name .. " to slot " .. slot)
        end
    elseif id:sub(1, 5) == "perk:" then
        local pid = id:sub(6)
        if devPlayerHasPerk(pid) then
            Mods.DevLog.push("sys", "[dev] already have perk: " .. pid)
            return
        end
        local perk = devPerkById(pid)
        if perk then
            Mods.Progression.applyPerk(player, perk)
            Mods.DevLog.push("sys", "[dev] perk " .. pid)
        end
    end
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
    if not saloon.charSheetTitleFont then
        saloon.charSheetTitleFont = Mods.Font.new(18)
    end
    if not saloon.charSheetBodyFont then
        saloon.charSheetBodyFont = Mods.Font.new(14)
    end
    local py = y + pad
    love.graphics.setFont(saloon.charSheetTitleFont)
    love.graphics.setColor(1, 0.88, 0.35)
    love.graphics.print("Character", x + pad, py)
    py = py + 26
    love.graphics.setFont(saloon.charSheetBodyFont)
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
        local _, lines = saloon.charSheetBodyFont:getWrap(ptext, tw)
        love.graphics.printf(ptext, x + pad, py, tw, "left")
        py = py + #lines * saloon.charSheetBodyFont:getHeight() + 8
    end
    local tw = w - 2 * pad
    local function drawWrappedBulletLines(lines, color)
        love.graphics.setColor(color[1], color[2], color[3], color[4] or 1)
        for _, line in ipairs(lines or {}) do
            local text = "• " .. line
            local _, wrapped = saloon.charSheetBodyFont:getWrap(text, tw)
            love.graphics.printf(text, x + pad + 4, py, tw - 4, "left")
            py = py + math.max(1, #wrapped) * saloon.charSheetBodyFont:getHeight() + 2
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

---------------------------------------------------------------------------
-- Asset loading
---------------------------------------------------------------------------
local function loadDecorSprite(name, path)
    if decor[name] then return end
    local ok, img = pcall(love.graphics.newImage, path)
    if ok then
        img:setFilter("nearest", "nearest")
        decor[name] = img
    end
end

local function loadDecorations()
    if decor._loaded then return end
    decor._loaded = true

    -- Bar assets
    loadDecorSprite("bar_counter", "assets/Bar_by_Styl0o/individuals sprite/bar.png")
    loadDecorSprite("shelf", "assets/Bar_by_Styl0o/individuals sprite/shelf.png")
    loadDecorSprite("stool", "assets/Bar_by_Styl0o/individuals sprite/stool.png")
    loadDecorSprite("bottles", "assets/Bar_by_Styl0o/individuals sprite/bottles.png")
    loadDecorSprite("floor_bar", "assets/Bar_by_Styl0o/individuals sprite/floor_bar.png")
    loadDecorSprite("greenboard", "assets/Bar_by_Styl0o/individuals sprite/Greenboard_weird_writing.png")
    loadDecorSprite("watch", "assets/Bar_by_Styl0o/individuals sprite/watch.png")
    loadDecorSprite("beam", "assets/Bar_by_Styl0o/individuals sprite/beam.png")
    loadDecorSprite("jars", "assets/Bar_by_Styl0o/individuals sprite/jars.png")
    loadDecorSprite("vase", "assets/Bar_by_Styl0o/individuals sprite/vase_flowers.png")
    loadDecorSprite("glass", "assets/Bar_by_Styl0o/individuals sprite/glass.png")

    -- More bar props
    loadDecorSprite("ampule", "assets/Bar_by_Styl0o/individuals sprite/ampule.png")
    loadDecorSprite("boxes", "assets/Bar_by_Styl0o/individuals sprite/boxes.png")
    loadDecorSprite("umbrella", "assets/Bar_by_Styl0o/individuals sprite/umbrella.png")

    -- Western props
    loadDecorSprite("wanted", "assets/wild_west_free_pack/wanted_pester.png")
    loadDecorSprite("fridge", "assets/Bar_by_Styl0o/individuals sprite/fridge.png")

    -- Better wooden floor tile
    loadDecorSprite("floor_wood", "assets/floor_wood.png")

    -- Casino tileset (roulette table)
    loadDecorSprite("slot_machine", "assets/slot.png")
    if decor.slot_machine and not slotMachineQuad then
        local sw, sh = decor.slot_machine:getDimensions()
        slotMachineQuad = love.graphics.newQuad(86, 27, 86, 229, sw, sh)
    end
    loadDecorSprite("casino_sheet", "assets/Bar_by_Styl0o/2D Top Down Pixel Art Tileset Casino/2D Top Down Pixel Art Tileset Casino/2D_TopDown_Tileset_Casino_640x512.png")
    if decor.casino_sheet and not rouletteTableQuad then
        local sw, sh = decor.casino_sheet:getDimensions()
        rouletteTableQuad = love.graphics.newQuad(292, 156, 108, 64, sw, sh)
    end

    -- Generated pixel art props
    loadDecorSprite("gen_window", "assets/saloon_props/window.png")
    loadDecorSprite("gen_barrel", "assets/saloon_props/barrel.png")
    loadDecorSprite("gen_piano", "assets/saloon_props/piano.png")
    loadDecorSprite("gen_poker_table", "assets/saloon_props/poker_table.png")
    loadDecorSprite("gen_clock", "assets/saloon_props/clock.png")
    loadDecorSprite("gen_crates", "assets/saloon_props/crates.png")
    loadDecorSprite("gen_spittoon", "assets/saloon_props/spittoon.png")
    loadDecorSprite("gen_chair", "assets/saloon_props/chair.png")
    loadDecorSprite("gen_lantern", "assets/saloon_props/lantern.png")
    loadDecorSprite("gen_antler", "assets/saloon_props/antler.png")

    do
        local pi = require("src.data.saloon_pixelinterior")
        local path = pi.sheets and pi.sheets.decor
        if path and not pixelInteriorDecorImg then
            local ok, img = pcall(love.graphics.newImage, path)
            if ok and img then
                img:setFilter("nearest", "nearest")
                pixelInteriorDecorImg = img
                local sw, sh = img:getDimensions()
                for quadName, qdef in pairs(pi.quads or {}) do
                    if qdef.sheet == "decor" then
                        pixelDecorQuads[quadName] = love.graphics.newQuad(qdef.x, qdef.y, qdef.w, qdef.h, sw, sh)
                        pixelDecorSizes[quadName] = { qdef.w, qdef.h }
                    end
                end
            end
        end
    end

    do
        local pi = require("src.data.saloon_pixelinterior")
        local path = pi.sheets and pi.sheets.cabinets
        if path and not pixelInteriorCabinetImg then
            local ok, img = pcall(love.graphics.newImage, path)
            if ok and img then
                img:setFilter("nearest", "nearest")
                pixelInteriorCabinetImg = img
                local sw, sh = img:getDimensions()
                for quadName, qdef in pairs(pi.quads or {}) do
                    if qdef.sheet == "cabinets" then
                        pixelCabinetQuads[quadName] = love.graphics.newQuad(qdef.x, qdef.y, qdef.w, qdef.h, sw, sh)
                        pixelCabinetSizes[quadName] = { qdef.w, qdef.h }
                    end
                end
            end
        end
    end

    -- Wall panel for visible side walls
    loadDecorSprite("wall_bar", "assets/Bar_by_Styl0o/individuals sprite/wall_bar.png")
end

---------------------------------------------------------------------------
-- Dust mote + draw helpers (all on Atmos to save upvalues)
---------------------------------------------------------------------------
local function spawnDustMote(roomW, floorY)
    return {
        x = math.random() * roomW,
        y = math.random() * (floorY - 20),
        vx = (math.random() - 0.5) * 4,
        vy = (math.random() - 0.5) * 1.5 - 0.3,
        life = math.random() * 6 + 3,
        maxLife = 0,
        size = math.random() < 0.3 and 2 or 1,
        alpha = 0,
    }
end

function Atmos.initDust()
    Atmos.dustMotes = {}
    local roomW = Mods.saloonRoom.width
    local floorY = Mods.saloonRoom.platforms[1].y
    for _ = 1, Atmos.DUST_COUNT do
        local m = spawnDustMote(roomW, floorY)
        m.maxLife = m.life
        m.alpha = math.random() * 0.3 + 0.1
        table.insert(Atmos.dustMotes, m)
    end
end

function Atmos.updateDust(dt)
    local roomW = Mods.saloonRoom.width
    local floorY = Mods.saloonRoom.platforms[1].y
    for i = #Atmos.dustMotes, 1, -1 do
        local m = Atmos.dustMotes[i]
        m.x = m.x + m.vx * dt
        m.y = m.y + m.vy * dt
        m.life = m.life - dt
        local ratio = m.life / m.maxLife
        if ratio > 0.8 then
            m.alpha = (1 - ratio) / 0.2 * 0.35
        elseif ratio < 0.2 then
            m.alpha = ratio / 0.2 * 0.35
        else
            m.alpha = 0.35
        end
        if m.life <= 0 or m.x < -10 or m.x > roomW + 10 or m.y > floorY then
            Atmos.dustMotes[i] = spawnDustMote(roomW, floorY)
            Atmos.dustMotes[i].maxLife = Atmos.dustMotes[i].life
        end
    end
end

-- === Structural elements ===

function Atmos.drawCeiling(roomW, ceilingY)
    -- Dark wooden ceiling planks
    love.graphics.setColor(0.14, 0.08, 0.04)
    love.graphics.rectangle("fill", 0, ceilingY, roomW, 6)
    -- Bottom edge highlight
    love.graphics.setColor(0.22, 0.13, 0.07)
    love.graphics.rectangle("fill", 0, ceilingY + 5, roomW, 1)
    -- Rafters/beams across ceiling
    love.graphics.setColor(0.18, 0.10, 0.05)
    love.graphics.rectangle("fill", 0, ceilingY + 6, roomW, 2)
end

function Atmos.drawSideWall(x, ceilingY, bottomY, isLeft)
    local wallW = 8
    local wallH = bottomY - ceilingY
    local wx = isLeft and x or (x - wallW)
    -- Main wall panel (extends to basement)
    love.graphics.setColor(0.16, 0.09, 0.05)
    love.graphics.rectangle("fill", wx, ceilingY, wallW, wallH)
    -- Vertical plank lines
    love.graphics.setColor(0.12, 0.07, 0.03)
    for i = 0, wallW - 1, 3 do
        love.graphics.rectangle("fill", wx + i, ceilingY, 1, wallH)
    end
    -- Inner edge highlight/shadow
    if isLeft then
        love.graphics.setColor(0.22, 0.14, 0.08)
        love.graphics.rectangle("fill", wx + wallW - 1, ceilingY, 1, wallH)
    else
        love.graphics.setColor(0.22, 0.14, 0.08)
        love.graphics.rectangle("fill", wx, ceilingY, 1, wallH)
    end
end

function Atmos.drawBasement(roomW, floorY, floorH)
    local baseY = floorY + floorH  -- just below main floor
    local bsmtFloorY = Mods.saloonRoom.basementFloorY or (baseY + 80)
    local bsmtFloorH = Mods.saloonRoom.basementFloorH or 20
    local bsmtH = bsmtFloorY - baseY

    -- Dark stone back wall
    love.graphics.setColor(0.07, 0.05, 0.03)
    love.graphics.rectangle("fill", 0, baseY, roomW, bsmtH)

    -- Stone brick pattern on back wall
    love.graphics.setColor(0.10, 0.07, 0.04)
    for row = 0, math.floor(bsmtH / 8) do
        local offX = (row % 2 == 0) and 0 or 6
        for bx = offX, roomW, 14 do
            love.graphics.rectangle("fill", bx + 1, baseY + row * 8 + 1, 11, 6)
        end
    end

    -- Mortar lines (darker)
    love.graphics.setColor(0.05, 0.03, 0.02, 0.5)
    for row = 0, math.floor(bsmtH / 8) do
        love.graphics.rectangle("fill", 0, baseY + row * 8, roomW, 1)
    end

    -- Top shadow (darkness below main floor planks)
    love.graphics.setColor(0.02, 0.01, 0.005, 0.9)
    love.graphics.rectangle("fill", 0, baseY, roomW, 4)

    -- Cobwebs in corners
    love.graphics.setColor(0.20, 0.18, 0.16, 0.15)
    love.graphics.rectangle("fill", 2, baseY + 5, 12, 2)
    love.graphics.rectangle("fill", 4, baseY + 7, 8, 1)
    love.graphics.rectangle("fill", roomW - 14, baseY + 5, 12, 2)
    love.graphics.rectangle("fill", roomW - 12, baseY + 7, 8, 1)

    -- A few barrels/crates stored in basement
    love.graphics.setColor(0.18, 0.12, 0.06)
    -- Barrel 1
    love.graphics.rectangle("fill", 40, bsmtFloorY - 14, 10, 14)
    love.graphics.setColor(0.12, 0.08, 0.04)
    love.graphics.rectangle("fill", 40, bsmtFloorY - 10, 10, 2)
    love.graphics.rectangle("fill", 40, bsmtFloorY - 5, 10, 2)
    -- Barrel 2
    love.graphics.setColor(0.16, 0.10, 0.05)
    love.graphics.rectangle("fill", 56, bsmtFloorY - 12, 9, 12)
    love.graphics.setColor(0.11, 0.07, 0.03)
    love.graphics.rectangle("fill", 56, bsmtFloorY - 8, 9, 2)
    -- Crate
    love.graphics.setColor(0.20, 0.14, 0.07)
    love.graphics.rectangle("fill", 600, bsmtFloorY - 16, 14, 16)
    love.graphics.setColor(0.14, 0.09, 0.04)
    love.graphics.rectangle("fill", 606, bsmtFloorY - 16, 2, 16)
    love.graphics.rectangle("fill", 600, bsmtFloorY - 9, 14, 2)

    -- Basement floor (stone)
    love.graphics.setColor(0.12, 0.09, 0.06)
    love.graphics.rectangle("fill", 0, bsmtFloorY, roomW, bsmtFloorH)
    love.graphics.setColor(0.15, 0.11, 0.07)
    for bx = 0, roomW, 16 do
        local bw = 13 + (bx * 3 % 5)
        love.graphics.rectangle("fill", bx + 1, bsmtFloorY + 1, bw, bsmtFloorH - 2)
    end
end

-- Quad anchored with bottom edge at footY (world Y)
function Atmos.drawPixelDecorFoot(quadName, x, footY, s)
    local img = pixelInteriorDecorImg
    local quad = pixelDecorQuads[quadName]
    local sz = pixelDecorSizes[quadName]
    if not (img and quad and sz) then return end
    local qh = sz[2]
    s = s or 1
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(img, quad, x, footY - qh * s, 0, s, s)
end

function Atmos.drawPixelCabinetTop(quadName, x, topY, s)
    local img = pixelInteriorCabinetImg
    local quad = pixelCabinetQuads[quadName]
    local sz = pixelCabinetSizes[quadName]
    if not (img and quad and sz) then return end
    s = s or 1
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(img, quad, x, topY, 0, s, s)
end

-- LRK floor lamp quad (default floor_lamp); falls back to gen_lantern on floor
function Atmos.drawBasementFloorLamp(x, bsmtFloorY, s, quadName)
    s = s or 1.08
    quadName = quadName or "floor_lamp"
    local quad = pixelDecorQuads[quadName]
    local sz = pixelDecorSizes[quadName]
    if pixelInteriorDecorImg and quad and sz then
        local qw, qh = sz[1], sz[2]
        love.graphics.setColor(1, 1, 1)
        local topY = bsmtFloorY - qh * s
        love.graphics.draw(pixelInteriorDecorImg, quad, x, topY, 0, s, s)
        local glowTy = BASEMENT_FLOOR_LAMP_GLOW_FROM_TOP_PX[quadName] or 9
        Atmos.drawLampGlow(x + qw * s * 0.5, topY + glowTy * s, s)
    elseif decor.gen_lantern then
        Atmos.drawAssetFromBottom("gen_lantern", x, bsmtFloorY, s * 1.15)
        local img = decor.gen_lantern
        local iw, ih = img:getDimensions()
        local ss = s * 1.15
        local topY = bsmtFloorY - ih * ss
        Atmos.drawLampGlow(x + iw * ss * 0.5, topY + math.min(12, ih * 0.22) * ss, ss)
    end
end

function Atmos.drawBasementWallLantern(x, y, s)
    local img = decor.gen_lantern
    if not img then return end
    s = s or 0.35
    local iw, ih = img:getDimensions()
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(img, x, y, 0, s, s)
    Atmos.drawLampGlow(x + iw * s * 0.5, y + ih * s * 0.22)
end

function Atmos.drawBasementLighting(roomW, floorY, floorH)
    local L = Mods.saloonRoom.decor
    if not L then return end
    local baseY = floorY + floorH
    local bsmtFloorY = Mods.saloonRoom.basementFloorY or (baseY + 80)
    local bsmtH = bsmtFloorY - baseY
    if bsmtH < 8 then return end

    if L.basementWallLanterns then
        for _, wl in ipairs(L.basementWallLanterns) do
            local lx = wl.x
            if lx and lx >= 0 and lx <= roomW then
                local ly = baseY + bsmtH * (wl.yFrac or 0.32)
                Atmos.drawBasementWallLantern(lx, ly, wl.scale or 0.35)
            end
        end
    end

    if L.basementFloorLamps then
        for _, fl in ipairs(L.basementFloorLamps) do
            local fx = fl.x
            if fx and fx >= 0 and fx <= roomW then
                Atmos.drawBasementFloorLamp(fx, bsmtFloorY, fl.scale or 1.08, fl.quad)
            end
        end
    end
end

function Atmos.drawPillar(x, ceilingY, floorY)
    -- BACKGROUND pillar: darker/muted, behind player
    local pillarW = 6
    local pillarH = floorY - ceilingY
    -- Main body (dark, recessed)
    love.graphics.setColor(0.18, 0.10, 0.05)
    love.graphics.rectangle("fill", x, ceilingY, pillarW, pillarH)
    -- Left highlight
    love.graphics.setColor(0.24, 0.14, 0.08)
    love.graphics.rectangle("fill", x, ceilingY, 1, pillarH)
    -- Right shadow
    love.graphics.setColor(0.12, 0.06, 0.03)
    love.graphics.rectangle("fill", x + pillarW - 1, ceilingY, 1, pillarH)
    -- Capital (top bracket)
    love.graphics.setColor(0.22, 0.13, 0.07)
    love.graphics.rectangle("fill", x - 2, ceilingY + 6, pillarW + 4, 3)
    love.graphics.rectangle("fill", x - 1, ceilingY + 9, pillarW + 2, 2)
    -- Base bracket
    love.graphics.rectangle("fill", x - 2, floorY - 4, pillarW + 4, 4)
    love.graphics.setColor(0.16, 0.09, 0.04)
    love.graphics.rectangle("fill", x - 1, floorY - 5, pillarW + 2, 1)
end

function Atmos.drawForegroundPillar(x, ceilingY, floorY)
    -- FOREGROUND pillar: normal/lighter color, opaque, drawn OVER player for depth
    local pillarW = 7
    local pillarH = floorY - ceilingY
    love.graphics.setColor(0.28, 0.17, 0.09)
    love.graphics.rectangle("fill", x, ceilingY, pillarW, pillarH)
    -- Left highlight
    love.graphics.setColor(0.38, 0.24, 0.14)
    love.graphics.rectangle("fill", x, ceilingY, 2, pillarH)
    -- Right shadow
    love.graphics.setColor(0.18, 0.10, 0.05)
    love.graphics.rectangle("fill", x + pillarW - 2, ceilingY, 2, pillarH)
    -- Capital
    love.graphics.setColor(0.34, 0.22, 0.12)
    love.graphics.rectangle("fill", x - 3, ceilingY + 6, pillarW + 6, 4)
    love.graphics.rectangle("fill", x - 2, ceilingY + 10, pillarW + 4, 2)
    -- Base
    love.graphics.rectangle("fill", x - 3, floorY - 5, pillarW + 6, 5)
    love.graphics.setColor(0.26, 0.16, 0.08)
    love.graphics.rectangle("fill", x - 2, floorY - 6, pillarW + 4, 1)
end

-- === Asset-based prop drawing ===

function Atmos.drawAssetFromBottom(name, x, floorY, s)
    local img = decor[name]
    if not img then return end
    local iw, ih = img:getDimensions()
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(img, x, floorY - ih * s, 0, s, s)
end

function Atmos.drawAssetFromBottomFlip(name, x, floorY, s)
    local img = decor[name]
    if not img then return end
    local iw, ih = img:getDimensions()
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(img, x + iw * s, floorY - ih * s, 0, -s, s)
end

function Atmos.drawWindow(wx, floorY, s)
    local img = decor.gen_window
    local windowY = floorY - 72  -- on the back wall, well below ceiling
    if img then
        local iw, ih = img:getDimensions()
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(img, wx, windowY, 0, s, s)
    else
        -- Procedural fallback: simple window frame with yellow interior
        local ww, wh = math.floor(40 * s), math.floor(40 * s)
        love.graphics.setColor(1.0, 0.88, 0.45, 0.6)
        love.graphics.rectangle("fill", wx + 2, windowY + 2, ww - 4, wh - 4)
        love.graphics.setColor(0.22, 0.13, 0.07)
        love.graphics.rectangle("line", wx, windowY, ww, wh)
        love.graphics.rectangle("fill", wx + math.floor(ww/2) - 1, windowY, 2, wh)
        love.graphics.rectangle("fill", wx, windowY + math.floor(wh/2) - 1, ww, 2)
    end
end

function Atmos.drawWindowGlow(wx, floorY, s)
    -- Warm yellow glow spilling from window
    local img = decor.gen_window
    local iw = img and img:getWidth() or 40
    local windowY = floorY - 72
    local cx = wx + iw * s * 0.5
    local wy = windowY + 10
    love.graphics.setBlendMode("add")
    -- Glow on wall around window
    for i = 1, 5 do
        local r = 10 + i * 7
        local a = 0.04 - i * 0.006
        if a > 0 then
            love.graphics.setColor(1.0, 0.88, 0.45, a)
            love.graphics.circle("fill", cx, wy, r, 16)
        end
    end
    -- Light shaft downward
    local shaftH = floorY - wy
    for i = 0, 3 do
        local a = 0.012 - i * 0.003
        if a > 0 then
            love.graphics.setColor(1.0, 0.90, 0.55, a)
            love.graphics.polygon("fill",
                cx - 8 - i * 2, wy + 8,
                cx + 8 + i * 2, wy + 8,
                cx + 20 + i * 3, wy + shaftH,
                cx - 20 - i * 3, wy + shaftH
            )
        end
    end
    love.graphics.setBlendMode("alpha")
end

function Atmos.drawLampGlow(x, y, radiusScale)
    radiusScale = radiusScale or 1
    love.graphics.setBlendMode("add")
    for i = 1, 4 do
        local r = (12 + i * 8) * radiusScale
        local a = 0.06 - i * 0.012
        if a > 0 then
            love.graphics.setColor(1.0, 0.85, 0.45, a)
            love.graphics.circle("fill", x, y, r, 16)
        end
    end
    love.graphics.setBlendMode("alpha")
end

function Atmos.drawBarrel(x, floorY, s)
    -- Procedural barrel that matches the pixel art style
    local bw = math.floor(18 * s)
    local bh = math.floor(24 * s)
    local by = floorY - bh
    -- Body
    love.graphics.setColor(0.30, 0.18, 0.08)
    love.graphics.rectangle("fill", x, by, bw, bh)
    -- Slight bulge (wider middle rows)
    love.graphics.setColor(0.33, 0.20, 0.10)
    love.graphics.rectangle("fill", x - 1, by + math.floor(bh * 0.3), bw + 2, math.floor(bh * 0.4))
    -- Metal bands
    love.graphics.setColor(0.20, 0.20, 0.22)
    local bandH = math.max(1, math.floor(2 * s))
    love.graphics.rectangle("fill", x - 1, by + math.floor(bh * 0.2), bw + 2, bandH)
    love.graphics.rectangle("fill", x - 1, by + math.floor(bh * 0.7), bw + 2, bandH)
    -- Top rim
    love.graphics.setColor(0.25, 0.15, 0.07)
    love.graphics.rectangle("fill", x, by, bw, math.max(1, math.floor(2 * s)))
    -- Left highlight
    love.graphics.setColor(0.38, 0.24, 0.12)
    love.graphics.rectangle("fill", x, by, math.max(1, math.floor(s)), bh)
    -- Right shadow
    love.graphics.setColor(0.18, 0.10, 0.04)
    love.graphics.rectangle("fill", x + bw - math.max(1, math.floor(s)), by, math.max(1, math.floor(s)), bh)
end

function Atmos.drawAntler(x, floorY)
    local img = decor.gen_antler
    if img then
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(img, x, floorY - 85, 0, 0.5, 0.5)
    else
        -- Procedural fallback
        love.graphics.setColor(0.35, 0.25, 0.15)
        local ay = floorY - 80
        love.graphics.rectangle("fill", x + 4, ay + 4, 8, 6)  -- plaque
        love.graphics.setColor(0.55, 0.45, 0.35)
        love.graphics.rectangle("fill", x, ay, 3, 8)
        love.graphics.rectangle("fill", x + 13, ay, 3, 8)
        love.graphics.rectangle("fill", x + 2, ay - 2, 2, 4)
        love.graphics.rectangle("fill", x + 12, ay - 2, 2, 4)
    end
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function applyOutcome(outcome)
    if not outcome then return end
    if outcome.message then message = outcome.message end
    if outcome.messageTimer then messageTimer = outcome.messageTimer end
    if outcome.perkOptions then perkOptions = outcome.perkOptions end
    if outcome.mode then
        mode = (outcome.mode == "main") and "walking" or outcome.mode
    end
end

local function continueGame()
    if roomManager then
        roomManager:startNewCycle()
        roomManager.needsNewRooms = true
    end
    if world and player then
        pcall(function() world:remove(player) end)
    end
    Mods.Gamestate.pop()
end

local function enterTestRoom()
    if roomManager then
        roomManager:injectTestRoom()
        roomManager.needsNewRooms = true
    end
    if world and player then
        pcall(function() world:remove(player) end)
    end
    Mods.Gamestate.pop()
end

local function findNearbyNPC()
    for _, npc in ipairs(npcs) do
        if npc:canInteract(player.x, player.y, player.w, player.h) then
            return npc
        end
    end
    return nil
end

local function nearSlotMachine()
    local sm = Mods.saloonRoom.slotMachine
    if not sm or not player then return false end
    local px = player.x + player.w / 2
    local py = player.y + player.h / 2
    local dx, dy = px - sm.cx, py - sm.cy
    return dx * dx + dy * dy <= sm.r * sm.r
end

--- Weapon floor: interact press picks up; hold sells gun for scrap
local weaponPickupInteractState = {}
local saloonWalkInteractConsumed = false

local function trySaloonWalkingInteract(key)
    if not Mods.Keybinds.matches("interact", key) then return false end
    if nearSlotMachine() and slotsGame then
        applyOutcome(slotsGame:enterTable(player.gold, "walking"))
        return true
    end
    if not monster.drunk and monster.img then
        local pcx = player.x + player.w / 2
        local pcy = player.y + player.h / 2
        local mw, mh = monster.img:getDimensions()
        local mcx = monster.x + mw * MONSTER_CAN_SCALE * 0.5
        local mcy = monster.y + mh * MONSTER_CAN_SCALE * 0.5
        local mdx = pcx - mcx
        local mdy = pcy - mcy
        if (mdx * mdx + mdy * mdy) <= 35 * 35 then
            monster.drunk = true
            player:consumeMonsterEnergy()
            message = "Full heal!"
            messageTimer = 2.5
            return true
        end
    end
    if wantedQuestStage == "available" and wantedPoster and wantedPoster.cx and wantedPoster.interactY then
        local pcx = player.x + player.w / 2
        local pcy = player.y + player.h / 2
        local qx = wantedPoster.cx
        local qy = wantedPoster.interactY
        local dx = pcx - qx
        local dy = pcy - qy
        if (dx * dx + dy * dy) <= wantedPoster.r2 then
            wantedQuestStage = "pending"
            -- TODO: later: show quest info UI, allow accept, and close.
            return true
        end
    end
    if nearbyNPC then
        if nearbyNPC.type == "dealer" then
            mode = "casino_menu"
        elseif nearbyNPC.type == "bartender" then
            if player and player.runMetadata then
                local RunMetadata = require("src.systems.run_metadata")
                RunMetadata.recordShopVisit(player.runMetadata, {
                    source = "saloon_shop_enter",
                    difficulty = difficulty,
                    gold_before = player.gold,
                })
            end
            mode = "shop"
        end
        return true
    end
    local pcx = player.x + player.w / 2
    local pcy = player.y + player.h / 2
    -- Test room door
    if testDoor then
        local tcx = testDoor.x + testDoor.w / 2
        local tcy = testDoor.y + testDoor.h / 2
        local tdx = pcx - tcx
        local tdy = pcy - tcy
        if tdx * tdx + tdy * tdy < 50 * 50 then
            enterTestRoom()
            return true
        end
    end
    local dcx = exitDoor.x + exitDoor.w / 2
    local dcy = exitDoor.y + exitDoor.h / 2
    local dx = pcx - dcx
    local dy = pcy - dcy
    if dx * dx + dy * dy < 50 * 50 then
        continueGame()
        return true
    end
    return false
end

---------------------------------------------------------------------------
-- State callbacks
---------------------------------------------------------------------------
function saloon:enter(_, _player, _roomManager)
    player = _player
    roomManager = _roomManager
    difficulty = _roomManager and _roomManager.difficulty or 1

    player.vx = 0
    player.vy = 0

    Mods.MusicDirector.suspendGameplay()

    -- Load persistent assets
    if not bgImage then
        local ok, img = pcall(love.graphics.newImage, "assets/backgrounds/saloonLobby.png")
        bgImage = ok and img or nil
    end
    if not doorSheet then
        local ok, img = pcall(love.graphics.newImage, "assets/SaloonDoor.png")
        if ok then
            doorSheet = img
            doorSheet:setFilter("nearest", "nearest")
            local sw, sh = doorSheet:getDimensions()
            for i = 0, 7 do
                doorQuads[i + 1] = love.graphics.newQuad(
                    i * DOOR_FRAME_SIZE, 0, DOOR_FRAME_SIZE, DOOR_FRAME_SIZE, sw, sh
                )
            end
        end
    end
    loadDecorations()

    -- Wanted quest poster placement (foreground pillar)
    wantedQuestStage = "available"
    wantedPoster.s = 0.30
    do
        local L = Mods.saloonRoom.decor or {}
        local pillarX = L.foregroundPillars and L.foregroundPillars[#L.foregroundPillars]
        if pillarX and decor.wanted then
            local iw, ih = decor.wanted:getDimensions()
            local pillarW = 7 -- must match Atmos.drawForegroundPillar
            local floorY = Mods.saloonRoom.platforms[1].y
            local ceilingY = floorY - 90
            local scale = wantedPoster.s
            local posterW = iw * scale
            local posterH = ih * scale
            wantedPoster.x = (pillarX + pillarW * 0.5) - posterW * 0.5
            wantedPoster.y = ceilingY + 32
            wantedPoster.cx = wantedPoster.x + posterW * 0.5
            wantedPoster.markerY = wantedPoster.y - 10
            -- Interaction anchor should be closer to the player's reachable height
            -- (use the middle-ish of the poster, not the floating marker).
            wantedPoster.interactY = wantedPoster.y + posterH * 0.55
        else
            wantedPoster.x, wantedPoster.y, wantedPoster.cx, wantedPoster.markerY, wantedPoster.interactY = 0, 0, 0, 0, 0
        end
    end

    -- Fonts
    fonts.title = Mods.Font.new(36)
    fonts.stat = Mods.Font.new(18)
    fonts.body = Mods.Font.new(16)
    fonts.card = Mods.Font.new(20)
    fonts.shopTitle = Mods.Font.new(24)
    fonts.default = Mods.Font.new(12)
    Mods.Cursor.setDefault()

    -- Create bump world
    world = Mods.bump.newWorld(32)

    -- Add platforms (only floor — bar counter is decorative only)
    platforms = {}
    for _, p in ipairs(Mods.saloonRoom.platforms) do
        local plat = { x = p.x, y = p.y, w = p.w, h = p.h, oneWay = p.oneWay or false, isPlatform = true }
        world:add(plat, plat.x, plat.y, plat.w, plat.h)
        table.insert(platforms, plat)
    end

    -- Add walls
    walls = {}
    for _, w in ipairs(Mods.saloonRoom.walls) do
        local wall = { x = w.x, y = w.y, w = w.w, h = w.h, isWall = true }
        world:add(wall, wall.x, wall.y, wall.w, wall.h)
        table.insert(walls, wall)
    end

    -- Add exit door (collision zone, passthrough)
    local d = Mods.saloonRoom.exitDoor
    exitDoor = { x = d.x, y = d.y, w = d.w, h = d.h, isDoor = true }
    world:add(exitDoor, exitDoor.x, exitDoor.y, exitDoor.w, exitDoor.h)

    -- Add test room door (collision zone, passthrough)
    local td = Mods.saloonRoom.testDoor
    if td then
        testDoor = { x = td.x, y = td.y, w = td.w, h = td.h, isDoor = true }
        world:add(testDoor, testDoor.x, testDoor.y, testDoor.w, testDoor.h)
    end

    -- Spawn NPCs — NO collision bodies, player walks freely in front of them
    npcs = {}
    for _, npcDef in ipairs(Mods.saloonRoom.npcs) do
        local npcConfig = {
            type = npcDef.type,
            x = npcDef.x,
            y = npcDef.y,
            w = 20,
            h = 32,
            facingRight = npcDef.facingRight,
            promptLabel = npcDef.promptLabel,
            scale = 1,
            interactRadius = 50,
        }

        if npcDef.type == "dealer" then
            npcConfig.promptLabel = npcDef.promptLabel or "[E] Gamble"
            -- Shuffle clips are 128² vs 80² idle; same character art is smaller in-frame after idle-based scaling
            local DEALER_ACTION_DRAW_SCALE = 128 / 80
            npcConfig.animCycleMin = 2.0
            npcConfig.animCycleMax = 5.8
            -- Drinking: same dealer pack as idle/shuffle (south / 80²) — not the player cowboy strip.
            npcConfig.anims = {
                {
                    name = "shuffle",
                    path = "assets/sprites/blackjack_dealer/animations/custom-Shuffles a deck of cards/south/",
                    speed = 0.3,
                    drawScale = DEALER_ACTION_DRAW_SCALE,
                },
                { name = "idle", path = "assets/sprites/blackjack_dealer/animations/breathing-idle/south/", speed = 0.3 },
                { name = "drinking", path = "assets/sprites/blackjack_dealer/animations/drinking/south/", speed = 0.22 },
            }
        elseif npcDef.type == "bartender" then
            npcConfig.promptLabel = npcDef.promptLabel or "[E] Buy Supplies"
            npcConfig.animCycleMin = 2.2
            npcConfig.animCycleMax = 6.0
            -- Prefer bartender’s own drinking (south) if exported; else player strip as last resort.
            local btDrink = "assets/sprites/bartender/animations/drinking/south/"
            if not love.filesystem.getInfo(btDrink .. "frame_000.png") then
                btDrink = "assets/sprites/cowboy_v2/animations/drinking/east/"
            end
            npcConfig.anims = {
                { name = "shaking", path = "assets/sprites/bartender/animations/shaking/south/", speed = 0.2 },
                { name = "idle", path = "assets/sprites/bartender/animations/breathing-idle/south/", speed = 0.3 },
                { name = "drinking", path = btDrink, speed = 0.22 },
            }
            npcConfig.spritePath = "assets/sprites/bartender/rotations/south.png"
        end

        local npc = Mods.NPC.new(npcConfig)
        -- NOT added to bump world — NPCs are decorative, player walks in front
        table.insert(npcs, npc)
    end

    -- Position player at spawn
    local sp = Mods.saloonRoom.playerSpawn
    player.x = sp.x
    player.y = sp.y
    player.grounded = false
    player.jumpCount = 0
    player.airborneFromWalkoff = false
    player.coyoteTimer = 0
    player.jumpBufferTimer = 0
    player.dashTimer = 0
    player.dashCooldown = 0
    world:add(player, player.x, player.y, player.w, player.h)

    -- Camera — snap to player spawn on enter
    camera = Mods.Camera(Mods.saloonRoom.playerSpawn.x, Mods.saloonRoom.playerSpawn.y)
    camera.scale = CAM_ZOOM
    cam.currentX = Mods.saloonRoom.playerSpawn.x
    cam.currentY = Mods.saloonRoom.playerSpawn.y
    cam.targetX = cam.currentX
    cam.targetY = cam.currentY

    -- Game systems
    blackjackGame = Mods.Blackjack.new()
    rouletteGame = Mods.Roulette.new()
    slotsGame = Mods.Slots.new()
    shop = Mods.Shop.new(difficulty, player, {
        run_metadata = player and player.runMetadata or nil,
        source = "saloon_shop",
        room_manager = roomManager,
    })
    pickups = {}
    bullets = {}
    weaponPickupInteractState = {}
    saloonWalkInteractConsumed = false
    Mods.DamageNumbers.clear()

    -- Monster Energy on the bar counter — reset each visit (top of can on countertop)
    monster.drunk = false
    local _floorY = Mods.saloonRoom.platforms[1].y
    local decorLayout = Mods.saloonRoom.decor
    local okM, imgM = pcall(love.graphics.newImage, "assets/monster.png")
    if okM and imgM then
        imgM:setFilter("nearest", "nearest")
        monster.img = imgM
    end
    do
        local scale = (decorLayout and decorLayout.barCounterScale) or 0.52
        local segments = (decorLayout and decorLayout.barCounterSegments) or 2
        if segments < 1 then segments = 1 end
        local barH = BAR_COUNTER_IMG_H * scale
        local barY = _floorY - barH
        local mw, mh = 32, 48
        if monster.img then
            mw, mh = monster.img:getDimensions()
        end
        local surfaceY = saloonBarCounterSurfaceY(barY, scale)
        monster.y = math.floor(surfaceY - mh * MONSTER_CAN_SCALE + 0.5)
        local totalBarW = BAR_COUNTER_IMG_W * scale * segments
        local bx = (decorLayout and decorLayout.barCounterX) or (Mods.saloonRoom.width - 178)
        local mOffX = (decorLayout and decorLayout.monsterCanOffsetX) or 0
        monster.x = math.floor(bx + totalBarW * 0.5 - mw * MONSTER_CAN_SCALE * 0.5 + 0.5 + mOffX)
    end

    mode = "walking"
    message = ""
    messageTimer = 0
    perkOptions = nil
    hoveredPerk = nil
    nearbyNPC = nil

    paused = false
    pauseMenuView = "main"
    pauseSelectedIndex = 1
    pauseHoverIndex = nil
    pauseSettingsTab = "video"
    pauseSettingsHover = nil
    pauseSettingsBindCapture = nil
    pauseSettingsSliderDragKey = nil
    characterSheetOpen = false
    devPanelOpen = false
    devPanelScroll = 0
    devPanelHover = nil
    devPanelPauseGameplay = true
    devShowHitboxes = true
    devPanelSearchQuery = ""
    devPanelSearchFocus = false
    saloonDevRebuildRows()

    -- Initialize atmospheric dust motes
    Atmos.initDust()
end

function saloon:leave()
    if world then
        for _, b in ipairs(bullets) do
            if world:hasItem(b) then
                world:remove(b)
            end
        end
    end
    bullets = {}
    if world and player then
        pcall(function() world:remove(player) end)
    end
end

---------------------------------------------------------------------------
-- Update
---------------------------------------------------------------------------
function saloon:update(dt)
    if paused then return end
    if devToolsEnabled() and devPanelOpen and devPanelPauseGameplay ~= false then return end

    if messageTimer > 0 then
        messageTimer = messageTimer - dt
    end

    if mode == "walking" then
        tryFlushCasinoGoldToFloor()

        do
            local mx, my = love.mouse.getPosition()
            local gx, gy = windowToGame(mx, my)
            local wx, wy = camera:worldCoords(gx, gy, 0, 0, GAME_WIDTH, GAME_HEIGHT)
            player.aimWorldX = wx
            player.aimWorldY = wy
            local mouseAimOn = love.mouse.isDown(1)
            if mouseAimOn then
                player.effectiveAimX, player.effectiveAimY = wx, wy
                player.keyboardAimMode = false
            else
                player.effectiveAimX, player.effectiveAimY = player:keyboardFallbackAimPoint()
                player.keyboardAimMode = true
            end
            do
                local ag = player:getActiveGun()
                local meleeWeapon = ag and ag.weapon_kind == "melee"
                player.inputFireHeld = not player.blocking and not characterSheetOpen
                    and (not meleeWeapon and mouseAimOn)
            end
        end

        player:update(dt, world, {})

        -- Manual hold-to-fire: ranged only (melee / knife = tap-only, same as game state)
        if love.mouse.isDown(1) and not characterSheetOpen and not player.blocking then
            local agHold = player:getActiveGun()
            if agHold and agHold.weapon_kind ~= "melee" then
                local bulletData = player:shoot(player.aimWorldX, player.aimWorldY)
                if bulletData and #bulletData > 0 then
                    for _, data in ipairs(bulletData) do
                        local b = Mods.Combat.spawnBullet(world, data)
                        table.insert(bullets, b)
                    end
                end
            end
        end

        Mods.Combat.updateBullets(bullets, dt, world, {}, player)
        local bi = #bullets
        while bi >= 1 do
            if not bullets[bi].alive then
                if world:hasItem(bullets[bi]) then
                    world:remove(bullets[bi])
                end
                table.remove(bullets, bi)
            end
            bi = bi - 1
        end

        for _, p in ipairs(pickups) do
            p:update(dt, world, player.x + player.w / 2, player.y + player.h / 2)
        end
        local pi = 1
        while pi <= #pickups do
            if not pickups[pi].alive then
                if world:hasItem(pickups[pi]) then
                    world:remove(pickups[pi])
                end
                table.remove(pickups, pi)
            else
                pi = pi + 1
            end
        end
        weaponPickupInteractState = Mods.Combat.advanceWeaponPickupInteraction(
            dt, pickups, player, world, weaponPickupInteractState
        )
        if not Mods.Keybinds.isDown("interact") then
            saloonWalkInteractConsumed = false
        end
        Mods.Combat.checkPickups(pickups, player, world)
        Mods.DamageNumbers.update(dt)
        Mods.ImpactFX.update(dt)
        Atmos.updateDust(dt)

        -- Clamp player to room bounds
        if player.x < 0 then player.x = 0 end
        if player.x + player.w > Mods.saloonRoom.width then
            player.x = Mods.saloonRoom.width - player.w
        end

        -- Dead Cells-style smooth camera with look-ahead
        local screenW, screenH = GAME_WIDTH, GAME_HEIGHT
        local viewW = screenW / CAM_ZOOM
        local viewH = screenH / CAM_ZOOM
        local px = player.x + player.w / 2
        local py = player.y + player.h / 2

        local lookX = 0
        if player.vx > 10 then
            lookX = cam.lookAheadX
        elseif player.vx < -10 then
            lookX = -cam.lookAheadX
        elseif player.facingRight then
            lookX = cam.lookAheadX * 0.5
        else
            lookX = -cam.lookAheadX * 0.5
        end

        local lookY = 0
        if player.grounded then
            lookY = cam.groundedY
        elseif player.vy and player.vy > 50 then
            lookY = cam.lookAheadY
        end

        cam.targetX = math.max(viewW / 2, math.min(Mods.saloonRoom.width - viewW / 2, px + lookX))
        cam.targetY = math.max(viewH / 2, math.min(Mods.saloonRoom.height - viewH / 2, py + lookY))

        local t = 1 - math.exp(-cam.lerpSpeed * dt)
        cam.currentX = cam.currentX + (cam.targetX - cam.currentX) * t
        cam.currentY = cam.currentY + (cam.targetY - cam.currentY) * t

        camera:lookAt(cam.currentX, cam.currentY)

        -- Update NPCs
        nearbyNPC = nil
        for _, npc in ipairs(npcs) do
            npc:update(dt)
            npc.promptVisible = false
        end

        local closest = findNearbyNPC()
        if closest then
            closest.promptVisible = true
            nearbyNPC = closest
        end

    elseif mode == "perk_selection" and perkOptions then
        local mx, my = windowToGame(love.mouse.getPosition())
        hoveredPerk = Mods.PerkCard.getHovered(perkOptions, mx, my)
    elseif mode == "blackjack" then
        local mx, my = windowToGame(love.mouse.getPosition())
        blackjackGame:updateHover(mx, my, GAME_WIDTH, GAME_HEIGHT)
        blackjackGame:update(dt, player)
    elseif mode == "roulette" then
        rouletteGame:update(dt, player)
    elseif mode == "slots" then
        slotsGame:update(dt, player)
    end
end

---------------------------------------------------------------------------
-- Input
---------------------------------------------------------------------------
function saloon:keypressed(key, scancode, isrepeat)
    local _, _, _, consoleH = getDebugConsoleLayout()
    if devToolsEnabled() and devPanelOpen then
        if devPanelSearchFocus and key == "backspace" then
            devPanelSearchQuery = (devPanelSearchQuery or ""):sub(1, -2)
            saloonDevApplySearchFilter()
            return
        end
        if devPanelSearchFocus and key == "tab" then
            devPanelSearchFocus = false
            return
        end
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
        elseif key == "escape" or key == "f2" then
            devPanelOpen = false
            devPanelHover = nil
            devPanelSearchFocus = false
        end
        return
    end

    if key == "f2" and devToolsEnabled() then
        openDevPanel()
        return
    end

    if DEBUG and not devPanelOpen then
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

    if paused and pauseMenuView == "settings" and pauseSettingsBindCapture then
        if key == "escape" then
            pauseSettingsBindCapture = nil
        else
            local normalized = Mods.Keybinds.normalizeCapturedKey(key)
            Mods.Settings.setKeybind(pauseSettingsBindCapture, normalized)
            Mods.Settings.save()
            pauseSettingsBindCapture = nil
        end
        return
    end

    if key == "escape" then
        if characterSheetOpen and not paused then
            characterSheetOpen = false
            return
        end
        if paused then
            if pauseMenuView == "settings" then
                pauseMenuView = "main"
                pauseSettingsBindCapture = nil
                pauseSettingsSliderDragKey = nil
            else
                paused = false
                pauseMenuView = "main"
                pauseSettingsSliderDragKey = nil
            end
            return
        end
        if mode == "walking" then
            paused = true
            pauseMenuView = "main"
            pauseSelectedIndex = 1
            pauseHoverIndex = nil
            return
        end
    end

    if paused then
        if pauseMenuView == "settings" then
            if key == "backspace" then
                pauseMenuView = "main"
                pauseSettingsBindCapture = nil
                pauseSettingsSliderDragKey = nil
            elseif key == "[" then
                pauseSettingsTab = Mods.SettingsPanel.cycleTab(pauseSettingsTab, -1)
            elseif key == "]" then
                pauseSettingsTab = Mods.SettingsPanel.cycleTab(pauseSettingsTab, 1)
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

    if mode == "walking" then
        if trySaloonWalkingInteract(key) then
            saloonWalkInteractConsumed = true
        elseif Mods.Keybinds.matches("interact", key) and player and world and pickups then
            if Mods.Combat.tryInteractPickupLoot(pickups, player, world) then
                saloonWalkInteractConsumed = true
            end
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
            player:reload()
        end
        if Mods.Keybinds.matches("melee", key) and not isrepeat then
            tryPrimaryMeleeTapFromPointer(true)
        end
        if key == "h" then
            player:spinHolster()
        end
        if key == "tab" then
            player:switchWeapon()
        end

    elseif mode == "casino_menu" then
        if key == "1" then
            applyOutcome(blackjackGame:enterTable(player.gold))
        elseif key == "2" then
            applyOutcome(rouletteGame:enterTable(player.gold))
        elseif key == "3" then
            applyOutcome(slotsGame:enterTable(player.gold, "casino_menu"))
        elseif key == "escape" or key == "backspace" then
            mode = "walking"
        end

    elseif mode == "blackjack" then
        if key == "escape" or key == "backspace" then
            if blackjackGame.state == "betting" then
                mode = "walking"
                return
            end
        end
        applyOutcome(blackjackGame:handleKey(key, player))

    elseif mode == "roulette" then
        if key == "escape" or key == "backspace" then
            if rouletteGame.state == "betting" then
                mode = "walking"
                return
            end
        end
        applyOutcome(rouletteGame:handleKey(key, player))

    elseif mode == "slots" then
        applyOutcome(slotsGame:handleKey(key, player))

    elseif mode == "shop" then
        local num = tonumber(key)
        if num and num >= 1 and num <= #shop.items then
            local success, msg = shop:buyItem(num, player)
            message = msg
            messageTimer = 2
        elseif key == "r" then
            local success, msg, cost = shop:reroll(player)
            if success then
                message = string.format("%s (-$%d)", msg or "Rerolled!", cost or 0)
            else
                message = msg or "Not enough gold"
            end
            messageTimer = 2
        elseif key == "escape" or key == "backspace" then
            if player and player.runMetadata then
                local RunMetadata = require("src.systems.run_metadata")
                RunMetadata.recordShopVisit(player.runMetadata, {
                    source = "saloon_shop_leave",
                    difficulty = difficulty,
                    gold_after = player.gold,
                })
            end
            mode = "walking"
        end

    elseif mode == "perk_selection" then
        local num = tonumber(key)
        if num and num >= 1 and num <= #perkOptions then
            Mods.Progression.applyPerk(player, perkOptions[num])
            local nextMode = blackjackGame:completePerkSelection()
            mode = (nextMode == "main") and "walking" or nextMode
            perkOptions = nil
        end
    end
end

function saloon:textinput(t)
    if not devToolsEnabled() or not devPanelOpen or not devPanelSearchFocus then return end
    if t and #t > 0 then
        local q = (devPanelSearchQuery or "") .. t
        if #q > 256 then return end
        devPanelSearchQuery = q
        saloonDevApplySearchFilter()
    end
end

function saloon:mousemoved(x, y, dx, dy)
    local gx, gy = x, y
    if devToolsEnabled() and devPanelOpen and devPanelRows then
        if not saloon.devPanelTitleFont then
            saloon.devPanelTitleFont = Mods.Font.new(16)
        end
        if not saloon.devPanelRowFont then
            saloon.devPanelRowFont = Mods.Font.new(13)
        end
        local px, py, pw, ph = getDevPanelLayout()
        if pointInRect(gx, gy, px, py, pw, ph) then
            devPanelHover = Mods.DevPanel.hitTest(devPanelRows, gx, gy, devPanelScroll, px, py, pw, ph, saloon.devPanelTitleFont, saloon.devPanelRowFont)
        else
            devPanelHover = nil
        end
        return
    end
    if paused then
        if pauseMenuView == "settings" and pauseSettingsSliderDragKey and saloon.pauseMenuButtonFont then
            local v = Mods.SettingsPanel.sliderValueFromPointerX(
                GAME_WIDTH, GAME_HEIGHT, pauseSettingsTab, saloon.pauseMenuButtonFont,
                pauseSettingsSliderDragKey, gx
            )
            if v then
                Mods.Settings.setVolumeKey(pauseSettingsSliderDragKey, v)
                Mods.Settings.save()
                Mods.Settings.apply()
            end
            return
        end
        pauseHoverIndex = nil
        if pauseMenuView == "main" then
            for i, r in ipairs(pauseMenuButtonLayout("large")) do
                if pauseHitRect(gx, gy, r) then
                    pauseHoverIndex = i
                    pauseSelectedIndex = i
                    break
                end
            end
        else
            if not saloon.pauseMenuButtonFont then
                saloon.pauseMenuButtonFont = Mods.Font.new(26)
            end
            local h = Mods.SettingsPanel.hitTest(GAME_WIDTH, GAME_HEIGHT, pauseSettingsTab, gx, gy, saloon.pauseMenuButtonFont)
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
    end
end

function saloon:mousepressed(x, y, button)
    local gx, gy = x, y
    if devToolsEnabled() and devPanelOpen and devPanelRows then
        if not saloon.devPanelTitleFont then
            saloon.devPanelTitleFont = Mods.Font.new(16)
        end
        if not saloon.devPanelRowFont then
            saloon.devPanelRowFont = Mods.Font.new(13)
        end
        local px, py, pw, ph = getDevPanelLayout()
        local consoleX, consoleY, consoleW, consoleH = getDebugConsoleLayout()
        local insidePanel = pointInRect(gx, gy, px, py, pw, ph)
        local insideConsole = pointInRect(gx, gy, consoleX - 4, consoleY - 4, consoleW + 8, consoleH)
        if insidePanel then
            if button == 1 then
                local hit = Mods.DevPanel.hitTest(devPanelRows, gx, gy, devPanelScroll, px, py, pw, ph, saloon.devPanelTitleFont, saloon.devPanelRowFont)
                if hit == Mods.DevPanel.HIT_SEARCH then
                    devPanelSearchFocus = true
                else
                    devPanelSearchFocus = false
                    if hit then
                        saloonDevApplyAction(hit)
                    end
                end
            end
            return
        end
        if insideConsole then
            return
        end
        return
    end
    if paused then
        if button ~= 1 then return end
        if pauseMenuView == "main" then
            for _, r in ipairs(pauseMenuButtonLayout("large")) do
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
            if not saloon.pauseMenuButtonFont then
                saloon.pauseMenuButtonFont = Mods.Font.new(26)
            end
            local h = Mods.SettingsPanel.hitTest(GAME_WIDTH, GAME_HEIGHT, pauseSettingsTab, gx, gy, saloon.pauseMenuButtonFont)
            local r = Mods.SettingsPanel.applyHit(h, player)
            if h and h.kind == "slider" then
                pauseSettingsSliderDragKey = h.key
            end
            if r then
                if r.setTab then pauseSettingsTab = r.setTab end
                if r.goBack then
                    pauseMenuView = "main"
                    pauseSettingsBindCapture = nil
                    pauseSettingsSliderDragKey = nil
                end
                if r.startBind then pauseSettingsBindCapture = r.startBind end
                if r.action then saloonSettingsDebugAction(r.action) end
            end
        end
        return
    end

    if mode == "perk_selection" and button == 1 and hoveredPerk then
        Mods.Progression.applyPerk(player, perkOptions[hoveredPerk])
        local nextMode = blackjackGame:completePerkSelection()
        mode = (nextMode == "main") and "walking" or nextMode
        perkOptions = nil
        return
    end
    if mode == "casino_menu" and button == 1 then
        local mx, my = gx, gy
        for _, r in ipairs(casinoMenuRects) do
            if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
                if r.id == "blackjack" then
                    applyOutcome(blackjackGame:enterTable(player.gold))
                elseif r.id == "roulette" then
                    applyOutcome(rouletteGame:enterTable(player.gold))
                elseif r.id == "slots" then
                    applyOutcome(slotsGame:enterTable(player.gold, "casino_menu"))
                elseif r.id == "back" then
                    mode = "walking"
                end
                return
            end
        end
    elseif mode == "blackjack" then
        local mx, my = gx, gy
        applyOutcome(blackjackGame:handleMousePressed(mx, my, button, GAME_WIDTH, GAME_HEIGHT, player))
    elseif mode == "roulette" then
        local mx, my = gx, gy
        applyOutcome(rouletteGame:handleMousePressed(mx, my, button, GAME_WIDTH, GAME_HEIGHT, player, fonts))
    elseif mode == "slots" then
        local mx, my = gx, gy
        applyOutcome(slotsGame:handleMousePressed(mx, my, button, GAME_WIDTH, GAME_HEIGHT, player))
    end

    if mode == "walking" and player and camera and world and not characterSheetOpen then
        if button == 1 then
            tryPrimaryMeleeTapFromPointer(false)
            -- Gun fire: handled each frame while LMB held (see saloon:update)
        elseif button == 2 then
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
                player:reload()
            end
        end
    end
end

function saloon:mousereleased(x, y, button)
    if button == 1 then
        pauseSettingsSliderDragKey = nil
    end
end

function saloon:wheelmoved(x, y)
    if not devToolsEnabled() then return end
    local mx, my = love.mouse.getPosition()
    local gx, gy = windowToGame(mx, my)
    local consoleX, consoleY, consoleW, consoleH = getDebugConsoleLayout()
    local overConsole = pointInRect(gx, gy, consoleX - 4, consoleY - 4, consoleW + 8, consoleH)
    if devPanelOpen then
        local px, py, pw, ph = getDevPanelLayout()
        if pointInRect(gx, gy, px, py, pw, ph) then
            devPanelScroll = devPanelScroll - y * 36
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

---------------------------------------------------------------------------
-- Drawing helpers
---------------------------------------------------------------------------
local function drawSprite(name, x, y, sx, sy)
    local img = decor[name]
    if not img then return end
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(img, x, y, 0, sx or 1, sy or 1)
end

local function drawSpriteFromBottom(name, x, footY, sx, sy)
    local img = decor[name]
    if not img then return end
    local _, h = img:getDimensions()
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(img, x, footY - h * (sy or 1), 0, sx or 1, sy or 1)
end

-- Wall doors: draw before floor props so plants / furniture stay in front (saloon:draw)
local function drawSaloonDoorSprites()
    if exitDoor then
        if doorSheet and #doorQuads > 0 then
            love.graphics.setColor(1, 1, 1)
            local scale = exitDoor.h / DOOR_FRAME_SIZE
            local drawX = exitDoor.x + exitDoor.w / 2 - (DOOR_FRAME_SIZE * scale) / 2
            local drawY = exitDoor.y + exitDoor.h - DOOR_FRAME_SIZE * scale
            love.graphics.draw(doorSheet, doorQuads[8], drawX, drawY, 0, scale, scale)
        else
            love.graphics.setColor(0.4, 0.25, 0.1)
            love.graphics.rectangle("fill", exitDoor.x, exitDoor.y, exitDoor.w, exitDoor.h)
            love.graphics.setColor(0.7, 0.5, 0.2)
            love.graphics.rectangle("line", exitDoor.x, exitDoor.y, exitDoor.w, exitDoor.h)
        end
    end
    if testDoor then
        if doorSheet and #doorQuads > 0 then
            love.graphics.setColor(1, 1, 1)
            local scale = testDoor.h / DOOR_FRAME_SIZE
            local drawX = testDoor.x + testDoor.w / 2 - (DOOR_FRAME_SIZE * scale) / 2
            local drawY = testDoor.y + testDoor.h - DOOR_FRAME_SIZE * scale
            love.graphics.draw(doorSheet, doorQuads[8], drawX, drawY, 0, scale, scale)
        else
            love.graphics.setColor(0.4, 0.25, 0.1)
            love.graphics.rectangle("fill", testDoor.x, testDoor.y, testDoor.w, testDoor.h)
            love.graphics.setColor(0.7, 0.5, 0.2)
            love.graphics.rectangle("line", testDoor.x, testDoor.y, testDoor.w, testDoor.h)
        end
    end
end

---------------------------------------------------------------------------
-- Main draw
---------------------------------------------------------------------------
function saloon:draw()
    local screenW = GAME_WIDTH
    local screenH = GAME_HEIGHT
    local roomW = Mods.saloonRoom.width
    local floorY = Mods.saloonRoom.platforms[1].y  -- top of floor

    -- Dark background
    love.graphics.setColor(0.08, 0.05, 0.03)
    love.graphics.rectangle("fill", 0, 0, screenW, screenH)

    camera:attach(0, 0, screenW, screenH)
    Mods.WorldInteractLabelBatch.clear()

    local L = Mods.saloonRoom.decor
    local ceilingY = floorY - 90
    local floorH = Mods.saloonRoom.platforms[1].h

    -- === LAYER 0: Background image (saloon interior walls) ===
    if bgImage then
        local viewW = screenW / CAM_ZOOM
        local viewH = screenH / CAM_ZOOM
        local bw, bh = bgImage:getDimensions()
        local scale = math.max(viewW / bw, viewH / bh)
        local camX, camY = camera:position()
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(bgImage, camX - (bw * scale) / 2, camY - (bh * scale) / 2, 0, scale, scale)
    end

    -- === LAYER 1: Ceiling + side walls (room structure, extending to basement) ===
    Atmos.drawCeiling(roomW, ceilingY)
    local wallBottomY = (Mods.saloonRoom.basementFloorY or floorY) + (Mods.saloonRoom.basementFloorH or 0)
    Atmos.drawSideWall(0, ceilingY, wallBottomY, true)
    Atmos.drawSideWall(roomW, ceilingY, wallBottomY, false)

    -- === LAYER 2: Back wall windows with warm glow ===
    if L.windows then
        for _, w in ipairs(L.windows) do
            Atmos.drawWindow(w.x, floorY, w.scale or 0.55)
            Atmos.drawWindowGlow(w.x, floorY, w.scale or 0.55)
        end
    end

    -- === LAYER 3: Back wall decorations ===
    -- Beam across ceiling
    drawSprite("beam", 0, ceilingY + 7, 2.0 * (roomW / 480), 0.7)

    -- Back pillars (floor-to-ceiling structural)
    if L.backPillars then
        for _, px in ipairs(L.backPillars) do
            Atmos.drawPillar(px, ceilingY, floorY)
        end
    end

    -- Hanging lamps + warm glow
    do
        local lampCount = math.max(5, math.floor(roomW / 120))
        local lampPositions = {}
        for i = 1, lampCount do
            local lx
            if lampCount <= 1 then
                lx = roomW * 0.5
            else
                lx = 50 + (i - 1) * ((roomW - 100) / (lampCount - 1))
            end
            drawSprite("ampule", lx, ceilingY + 10, 0.8, 0.8)
            lampPositions[i] = lx
        end
        for _, lx in ipairs(lampPositions) do
            Atmos.drawLampGlow(lx + 4, ceilingY + 22)
        end
    end

    -- Fridge
    drawSpriteFromBottom("fridge", L.fridgeX, floorY, 1.0, 1.0)
    -- Back bar shelving
    local shelfSX, shelfSY = 0.6, 0.5
    if decor.shelf then
        local shelf2Off = (L.shelfSecondOffsetX) or math.floor(decor.shelf:getWidth() * shelfSX - 2)
        drawSprite("shelf", L.shelfX, floorY - 60, shelfSX, shelfSY)
        drawSprite("shelf", L.shelfX + shelf2Off, floorY - 60, shelfSX, shelfSY)
        drawSprite("bottles", L.bottlesX, floorY - 52, 0.7, 0.7)
        drawSprite("bottles", L.bottlesX + shelf2Off, floorY - 52, 0.7, 0.7)
        drawSprite("jars", L.jarsX, floorY - 50, 0.7, 0.7)
        drawSprite("jars", L.jarsX + shelf2Off, floorY - 50, 0.7, 0.7)
    else
        drawSprite("bottles", L.bottlesX, floorY - 52, 0.7, 0.7)
        drawSprite("jars", L.jarsX, floorY - 50, 0.7, 0.7)
    end
    if L.backBarCabinets then
        for _, cab in ipairs(L.backBarCabinets) do
            local cabX = cab.x
            if cab.quad and cabX and cabX >= 0 and cabX <= roomW then
                Atmos.drawPixelCabinetTop(cab.quad, cabX, floorY + (cab.yOffset or -56), cab.scale or 1.0)
            end
        end
    end
    -- Greenboard in lounge zone
    drawSprite("greenboard", L.greenboardX, floorY - 70, 0.6, 0.6)
    -- Wall clock (generated asset, NOT on shelves)
    if L.clockX then
        if decor.gen_clock then
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(decor.gen_clock, L.clockX, floorY - 82, 0, 0.45, 0.45)
        else
            drawSprite("watch", L.clockX, floorY - 75, 0.6, 0.6)
        end
    end
    -- Antler trophy
    if L.antlerX then
        Atmos.drawAntler(L.antlerX, floorY)
    end
    -- Wanted posters on left wall
    drawSprite("wanted", L.wantedX, floorY - 55, 0.35, 0.35)

    -- === LAYER 4: Floor with depth shading ===
    if decor.floor_wood then
        local fw, fh = decor.floor_wood:getDimensions()
        local tileScale = 1.0
        local tw = fw * tileScale
        local th = fh * tileScale
        local row = 0
        for tx = 0, roomW, tw do
            local shade = (row % 2 == 0) and 1.0 or 0.88
            love.graphics.setColor(shade, shade, shade)
            love.graphics.draw(decor.floor_wood, tx, floorY, 0, tileScale, tileScale)
            love.graphics.setColor(shade * 0.92, shade * 0.92, shade * 0.92)
            love.graphics.draw(decor.floor_wood, tx, floorY + th, 0, tileScale, tileScale)
            row = row + 1
        end
    elseif decor.floor_bar then
        love.graphics.setColor(1, 1, 1)
        local fw, fh = decor.floor_bar:getDimensions()
        local floorScale = roomW / fw
        love.graphics.draw(decor.floor_bar, 0, floorY, 0, floorScale, floorScale)
    else
        love.graphics.setColor(0.25, 0.15, 0.08)
        love.graphics.rectangle("fill", 0, floorY, roomW, 32)
    end
    -- Floor edge shadow
    love.graphics.setColor(0, 0, 0, 0.18)
    love.graphics.rectangle("fill", 0, floorY, roomW, 1)

    -- === LAYER 4b: Basement beneath floor ===
    Atmos.drawBasement(roomW, floorY, floorH)
    Atmos.drawBasementLighting(roomW, floorY, floorH)

    -- === LAYER 4c: Door sprites (back wall — before floor props so props draw on top) ===
    drawSaloonDoorSprites()

    -- === LAYER 5: Floor-level props ===
    -- Barrels (procedural — matches pixel art style better)
    if L.barrels then
        for _, b in ipairs(L.barrels) do
            local s = b.scale or 0.6
            Atmos.drawBarrel(b.x, floorY, s)
        end
    end

    -- Crate stacks (boxes asset at bigger scale)
    if L.crates then
        for _, c in ipairs(L.crates) do
            local s = c.scale or 0.65
            drawSpriteFromBottom("boxes", c.x, floorY, s, s)
        end
    end

    -- Spittoon
    if L.spittoonX then
        Atmos.drawAssetFromBottom("gen_spittoon", L.spittoonX, floorY, 0.35)
    end

    -- Piano (generated asset)
    if L.pianoX then
        Atmos.drawAssetFromBottom("gen_piano", L.pianoX, floorY, 0.55)
    end

    -- Poker table removed (didn't fit visually)

    -- Chairs near poker table
    if L.chairs then
        for _, ch in ipairs(L.chairs) do
            if ch.flip then
                Atmos.drawAssetFromBottomFlip("gen_chair", ch.x, floorY, 0.4)
            else
                Atmos.drawAssetFromBottom("gen_chair", ch.x, floorY, 0.4)
            end
        end
    end

    -- Potted plants (Pixel Interior LRK decorations sheet)
    if L.saloonPlants then
        for _, sp in ipairs(L.saloonPlants) do
            local qn = sp.quad
            local px = sp.x
            if qn and px and px >= 0 and px <= roomW then
                Atmos.drawPixelDecorFoot(qn, px, floorY, sp.scale or 0.92)
            end
        end
    end

    -- === LAYER 6: NPCs (behind counter/table) ===
    for _, npc in ipairs(npcs) do
        npc:draw()
    end

    -- === LAYER 7a: Multiple slot machines in gambling zone ===
    if decor.slot_machine and slotMachineQuad then
        local slots = Mods.saloonRoom.slotMachines
        if slots then
            for _, sm in ipairs(slots) do
                local smScale = sm.scale or 0.195
                local iw, ih = 86, 229
                local drawH = ih * smScale
                love.graphics.setColor(1, 1, 1)
                love.graphics.draw(decor.slot_machine, slotMachineQuad, sm.x, floorY - drawH, 0, smScale, smScale)
            end
        end
    end

    -- === LAYER 7b: Roulette table in front of dealer ===
    if decor.casino_sheet and rouletteTableQuad then
        local tableScale = 0.4
        local tableW = 108 * tableScale
        local tableH = 64 * tableScale
        local dealerX = Mods.saloonRoom.npcs[1].x
        local tableX = dealerX + 10 - tableW / 2
        local woodH = 6
        local woodTopY = floorY - woodH
        love.graphics.setColor(0.30, 0.18, 0.08)
        love.graphics.rectangle("fill", tableX, woodTopY, tableW, woodH)
        love.graphics.setColor(0.22, 0.13, 0.06)
        love.graphics.rectangle("fill", tableX, floorY - 1, tableW, 1)
        local feltY = woodTopY - tableH + 8
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(decor.casino_sheet, rouletteTableQuad, tableX, feltY, 0, tableScale, tableScale)
        love.graphics.setColor(0.40, 0.25, 0.12)
        love.graphics.rectangle("fill", tableX, woodTopY, tableW, 1)
    end

    -- === LAYER 7c: Bar counter ===
    local barScale, barW, _, barY, totalBarW, barSegments = saloonBarGeometry(floorY)
    if decor.bar_counter then
        love.graphics.setColor(1, 1, 1)
        local barX = L.barCounterX
        local seam = 1
        for seg = 0, barSegments - 1 do
            local sx = barX + seg * (barW - seam)
            love.graphics.draw(decor.bar_counter, sx, barY, 0, barScale, barScale)
        end
    end

    -- Umbrella: left end of bar, leans on counter (drawn after bar so it sits on the front edge)
    if decor.umbrella then
        local uScale = (L.umbrellaScale) or 0.55
        local lean = (L.umbrellaLeanRad) or 0.2
        local offX = (L.umbrellaBarOffsetX ~= nil) and L.umbrellaBarOffsetX or -5
        local img = decor.umbrella
        local iw, ih = img:getDimensions()
        local uw, uh = iw * uScale, ih * uScale
        local footX = L.barCounterX + offX
        love.graphics.setColor(1, 1, 1)
        love.graphics.push()
        love.graphics.translate(footX + uw * 0.5, floorY)
        love.graphics.rotate(lean)
        love.graphics.translate(-uw * 0.5, -uh)
        love.graphics.draw(img, 0, 0, 0, uScale, uScale)
        love.graphics.pop()
    end

    -- Stools — sporadic placement (slight random-looking offsets baked in)
    if decor.stool then
        local stoolScale = 0.5
        local nStools = (L.stoolCount) or 7
        if nStools < 1 then nStools = 1 end
        local sw = decor.stool:getWidth() * stoolScale
        local gapB = (L.stoolGapBetween) or 8
        local rowW = nStools * sw + (nStools - 1) * gapB
        local stoolOff = (L.stoolStartOffsetX) or 0
        local stoolStartX = L.barCounterX + math.floor((totalBarW - rowW) / 2 + 0.5) + stoolOff
        -- Sporadic offsets: some stools nudged or slightly scaled differently
        local offsets = { 0, 3, -1, 5, -2, 1, -3 }
        local scales = { 0.50, 0.48, 0.50, 0.52, 0.50, 0.49, 0.50 }
        for i = 0, nStools - 1 do
            local off = offsets[(i % #offsets) + 1] or 0
            local sc = scales[(i % #scales) + 1] or stoolScale
            drawSpriteFromBottom("stool", stoolStartX + i * (sw + gapB) + off, floorY, sc, sc)
        end
    end

    -- Beer mugs on countertop
    local glassFootY = saloonBarCounterSurfaceY(barY, barScale)
    local glassS = 0.7
    local bx0 = L.barCounterX
    drawSpriteFromBottom("glass", bx0 + math.floor(totalBarW * 0.10), glassFootY, glassS, glassS)
    drawSpriteFromBottom("glass", bx0 + math.floor(totalBarW * 0.28), glassFootY, 0.65, 0.65)
    drawSpriteFromBottom("glass", bx0 + math.floor(totalBarW * 0.74), glassFootY, 0.6, 0.6)

    -- Vase on bar counter
    if decor.vase then
        local vaseS = 0.62
        local vw = decor.vase:getWidth() * vaseS
        local vaseX = bx0 + math.floor(totalBarW * 0.50) - math.floor(vw * 0.5)
        drawSpriteFromBottom("vase", vaseX, glassFootY, vaseS, vaseS)
    end

    -- Monster Energy on bar counter
    if not monster.drunk and monster.img then
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(monster.img, monster.x, monster.y, 0, MONSTER_CAN_SCALE, MONSTER_CAN_SCALE)
    end

    -- === LAYER 8: Door interaction labels (sprites drawn in LAYER 4c) ===
    if exitDoor then
        if mode == "walking" and player then
            local pcx = player.x + player.w / 2
            local pcy = player.y + player.h / 2
            local dcx = exitDoor.x + exitDoor.w / 2
            local dcy = exitDoor.y + exitDoor.h / 2
            local ddx = pcx - dcx
            local ddy = pcy - dcy
            if ddx * ddx + ddy * ddy < 50 * 50 then
                love.graphics.setFont(fonts.default)
                local label = "[E] Hit the Road"
                local tw = fonts.default:getWidth(label)
                love.graphics.setColor(0, 0, 0, 0.7)
                love.graphics.print(label, math.floor(dcx - tw / 2) + 1, math.floor(exitDoor.y - 14) + 1)
                love.graphics.setColor(1, 0.9, 0.5)
                love.graphics.print(label, math.floor(dcx - tw / 2), math.floor(exitDoor.y - 14))
            end
        end
    end
    if testDoor then
        if mode == "walking" and player then
            local pcx = player.x + player.w / 2
            local pcy = player.y + player.h / 2
            local tcx = testDoor.x + testDoor.w / 2
            local tcy = testDoor.y + testDoor.h / 2
            local tdx = pcx - tcx
            local tdy = pcy - tcy
            if tdx * tdx + tdy * tdy < 50 * 50 then
                love.graphics.setFont(fonts.default)
                local label = "[E] Test Room"
                local tw = fonts.default:getWidth(label)
                love.graphics.setColor(0, 0, 0, 0.7)
                love.graphics.print(label, math.floor(tcx - tw / 2) + 1, math.floor(testDoor.y - 14) + 1)
                love.graphics.setColor(0.5, 1.0, 0.5)
                love.graphics.print(label, math.floor(tcx - tw / 2), math.floor(testDoor.y - 14))
            end
        end
    end

    -- === LAYER 9: Dust motes ===
    for _, m in ipairs(Atmos.dustMotes) do
        love.graphics.setColor(1.0, 0.95, 0.80, m.alpha)
        love.graphics.rectangle("fill", math.floor(m.x), math.floor(m.y), m.size, m.size)
    end

    -- === LAYER 10: Pickups ===
    for _, p in ipairs(pickups) do
        p:draw(player, camera, 0, 0, nil, pickups)
    end
    Mods.WorldInteractLabelBatch.flush()

    -- === LAYER 11: Player ===
    if player then
        love.graphics.setColor(1, 1, 1)
        player:draw()
    end
    for _, b in ipairs(bullets) do
        b:draw()
    end
    Mods.ImpactFX.draw()
    Mods.DamageNumbers.draw()

    -- === LAYER 12: FOREGROUND elements (opaque, in front of player for depth) ===
    if L.foregroundPillars then
        for _, px in ipairs(L.foregroundPillars) do
            Atmos.drawForegroundPillar(px, ceilingY, floorY)
        end
    end
    -- Wanted poster on a foreground pillar (with floating quest marker)
    if decor.wanted and wantedPoster and wantedPoster.y and wantedPoster.y ~= 0 then
        drawSprite("wanted", wantedPoster.x, wantedPoster.y, wantedPoster.s, wantedPoster.s)
        if mode == "walking" and wantedQuestStage == "available" and wantedPoster.markerY then
            local bob = math.sin(love.timer.getTime() * 6) * 1.2
            local mx = math.floor(wantedPoster.cx - 2)
            local my = math.floor(wantedPoster.markerY + bob)
            love.graphics.setFont(fonts.default)
            love.graphics.setColor(0, 0, 0, 0.65)
            love.graphics.print("!", mx + 1, my + 1)
            love.graphics.setColor(1, 0.85, 0.25, 1)
            love.graphics.print("!", mx, my)
            love.graphics.setColor(1, 1, 1, 1)

            -- Nearby interaction hint
            if player then
                local pcx = player.x + player.w / 2
                local pcy = player.y + player.h / 2
                local dx = pcx - wantedPoster.cx
                local dy = pcy - wantedPoster.interactY
                if (dx * dx + dy * dy) <= wantedPoster.r2 then
                    local label = "[E] Quest"
                    local tw = fonts.default:getWidth(label)
                    -- Keep quest text steady (no bobbing), so it doesn't feel jumpy.
                    local qy = math.floor(wantedPoster.markerY + 10)
                    love.graphics.setFont(fonts.default)
                    love.graphics.setColor(0, 0, 0, 0.7)
                    love.graphics.print(label, math.floor(wantedPoster.cx - tw / 2) + 1, qy + 1)
                    love.graphics.setColor(1, 0.85, 0.25, 1)
                    love.graphics.print(label, math.floor(wantedPoster.cx - tw / 2), qy)
                    love.graphics.setColor(1, 1, 1, 1)
                end
            end
        end
    end

    -- === LAYER 13: NPC prompts (always on top in world space) ===
    for _, npc in ipairs(npcs) do
        npc:drawSpeech()
        npc:drawPrompt()
    end

    -- Monster Energy prompt
    if mode == "walking" and not monster.drunk and monster.img and player then
        local pcx = player.x + player.w / 2
        local pcy = player.y + player.h / 2
        local mw, mh = monster.img:getDimensions()
        local mcx = monster.x + mw * MONSTER_CAN_SCALE * 0.5
        local mcy = monster.y + mh * MONSTER_CAN_SCALE * 0.5
        local mdx = pcx - mcx
        local mdy = pcy - mcy
        if (mdx * mdx + mdy * mdy) <= 35 * 35 then
            love.graphics.setFont(fonts.default)
            local label = "[E] Drink"
            local tw = fonts.default:getWidth(label)
            local bob = math.sin(love.timer.getTime() * 3) * 1.5
            love.graphics.setColor(0, 0, 0, 0.7)
            love.graphics.print(label, math.floor(mcx - tw / 2) + 1, math.floor(monster.y - 10 + bob) + 1)
            love.graphics.setColor(0.4, 1, 0.4)
            love.graphics.print(label, math.floor(mcx - tw / 2), math.floor(monster.y - 10 + bob))
        end
    end

    if mode == "walking" and player and nearSlotMachine() then
        love.graphics.setFont(fonts.default)
        local label = "[E] Slots"
        local sm = Mods.saloonRoom.slotMachine
        local tw = fonts.default:getWidth(label)
        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.print(label, math.floor(sm.cx - tw / 2) + 1, math.floor(sm.cy - 42) + 1)
        love.graphics.setColor(1, 0.9, 0.5)
        love.graphics.print(label, math.floor(sm.cx - tw / 2), math.floor(sm.cy - 42))
    end

    -- === LAYER 14: Warm ambient wash ===
    love.graphics.setBlendMode("multiply", "premultiplied")
    love.graphics.setColor(1.0, 0.97, 0.90, 1.0)
    love.graphics.rectangle("fill", 0, ceilingY, roomW, Mods.saloonRoom.height)
    love.graphics.setBlendMode("alpha")

    if DEBUG and devShowHitboxes and world then
        love.graphics.setColor(0, 1, 0, 0.3)
        local items, len = world:getItems()
        for i = 1, len do
            local wx, wy, ww, wh = world:getRect(items[i])
            love.graphics.rectangle("line", wx, wy, ww, wh)
        end
        love.graphics.setColor(1, 1, 1, 1)
    end

    camera:detach()

    -----------------------------------------------------------------------
    -- Overlay UIs (screen space)
    -----------------------------------------------------------------------
    if mode ~= "walking" then
        love.graphics.setColor(0, 0, 0, 0.65)
        love.graphics.rectangle("fill", 0, 0, screenW, screenH)

        if mode == "casino_menu" then
            drawCasinoMenu(screenW, screenH)
        elseif mode == "blackjack" then
            blackjackGame:draw(screenW, screenH, fonts)
        elseif mode == "roulette" then
            rouletteGame:draw(screenW, screenH, fonts, player)
        elseif mode == "slots" then
            slotsGame:draw(screenW, screenH, fonts)
        elseif mode == "shop" then
            drawShop(screenW, screenH)
        elseif mode == "perk_selection" then
            Mods.PerkCard.draw(perkOptions, nil, hoveredPerk)
        end
    end

    if not DEBUG then
        Mods.DevLog.drawOverlay(screenW, screenH)
    end

    -- Message toast
    if messageTimer > 0 then
        love.graphics.setFont(fonts.body)
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.printf(message, 1, screenH - 49, screenW, "center")
        love.graphics.setColor(1, 1, 0.5)
        love.graphics.printf(message, 0, screenH - 50, screenW, "center")
    end

    if characterSheetOpen and not paused then
        love.graphics.setColor(0, 0, 0, 0.35)
        love.graphics.rectangle("fill", 0, 0, screenW, screenH)
        drawCharacterSheet()
    end

    if paused then
        love.graphics.setColor(0, 0, 0, 0.48)
        love.graphics.rectangle("fill", 0, 0, screenW, screenH)

        if not saloon.pauseTitleFont then
            saloon.pauseTitleFont = Mods.Font.new(32)
        end
        if not saloon.pauseMenuButtonFont then
            saloon.pauseMenuButtonFont = Mods.Font.new(26)
        end
        if not saloon.pauseHintFont then
            saloon.pauseHintFont = Mods.Font.new(15)
        end
        if not saloon.pauseSettingsBodyFont then
            saloon.pauseSettingsBodyFont = Mods.Font.new(16)
        end

        if pauseMenuView == "main" then
            love.graphics.setFont(saloon.pauseTitleFont)
            love.graphics.setColor(1, 0.86, 0.28, 0.95)
            love.graphics.printf("PAUSED", 0, screenH * 0.16, screenW, "center")

            local rects = pauseMenuButtonLayout("large")
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
                love.graphics.setFont(saloon.pauseMenuButtonFont)
                love.graphics.printf(
                    r.label,
                    r.x,
                    Mods.TextLayout.printfYCenteredInRect(saloon.pauseMenuButtonFont, r.y, r.h),
                    r.w,
                    "center"
                )
            end

            love.graphics.setFont(saloon.pauseHintFont)
            love.graphics.setColor(0.45, 0.45, 0.48)
            love.graphics.printf("Arrows / mouse  ·  Enter  ·  ESC to resume", 0, screenH * 0.88, screenW, "center")
        else
            Mods.SettingsPanel.draw(screenW, screenH, pauseSettingsTab, {
                title = saloon.pauseTitleFont,
                tab = saloon.pauseMenuButtonFont,
                row = saloon.pauseSettingsBodyFont,
                hint = saloon.pauseHintFont,
            }, pauseSettingsHover, pauseSettingsBindCapture)
        end
    end

    if DEBUG and player then
        local es = player:getEffectiveStats()
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
        if not saloon.debugFont then
            saloon.debugFont = Mods.Font.new(11)
        end
        love.graphics.setFont(saloon.debugFont)

        local panelX = screenW - 260
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

        local consoleX, consoleY, consoleW, consoleH = getDebugConsoleLayout()
        Mods.DevLog.drawConsole(consoleX, consoleY, consoleW, consoleH)
    end

    if devToolsEnabled() and devPanelOpen and devPanelRows and player then
        love.graphics.setColor(0, 0, 0, 0.38)
        love.graphics.rectangle("fill", 0, 0, screenW, screenH)
        if not saloon.devPanelTitleFont then
            saloon.devPanelTitleFont = Mods.Font.new(16)
        end
        if not saloon.devPanelRowFont then
            saloon.devPanelRowFont = Mods.Font.new(13)
        end
        devClampScroll()
        local px, py, pw, ph = getDevPanelLayout()
        Mods.DevPanel.draw(devPanelRows, devPanelScroll, px, py, pw, ph, devPanelHover, {
            title = saloon.devPanelTitleFont,
            row = saloon.devPanelRowFont,
        }, {
            query = devPanelSearchQuery or "",
            focused = devPanelSearchFocus,
            hover = devPanelHover == Mods.DevPanel.HIT_SEARCH,
        })
    end

    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(fonts.default)
end

---------------------------------------------------------------------------
-- Sub-draw functions
---------------------------------------------------------------------------
local function getCasinoMenuLayout(screenW, screenH)
    local btnW = math.min(280, screenW * 0.35)
    local btnH = 60
    local gap = 16
    local cx = screenW * 0.5
    local titleY = screenH * 0.18
    local startY = titleY + 72
    local rects = {}
    rects[1] = { id = "blackjack", x = cx - btnW * 0.5, y = startY, w = btnW, h = btnH,
                 label = "BLACKJACK", sublabel = "Beat the dealer to 21" }
    rects[2] = { id = "roulette", x = cx - btnW * 0.5, y = startY + btnH + gap, w = btnW, h = btnH,
                 label = "ROULETTE", sublabel = "Spin the wheel, test your luck" }
    rects[3] = { id = "slots", x = cx - btnW * 0.5, y = startY + (btnH + gap) * 2, w = btnW, h = btnH,
                 label = "SLOTS", sublabel = "Three reels, match them all" }
    local backW = math.min(160, btnW * 0.6)
    local backH = 44
    rects[4] = { id = "back", x = cx - backW * 0.5, y = startY + (btnH + gap) * 3 + 10, w = backW, h = backH,
                 label = "BACK", sublabel = nil }
    casinoMenuRects = rects
    return rects, titleY
end

function drawCasinoMenu(screenW, screenH)
    local rects, titleY = getCasinoMenuLayout(screenW, screenH)
    local mx, my = 0, 0
    if windowToGame then
        mx, my = windowToGame(love.mouse.getPosition())
    end

    -- Title with glow
    love.graphics.setFont(fonts.shopTitle or fonts.title)
    love.graphics.setColor(1, 0.75, 0.1, 0.15)
    love.graphics.printf("CASINO", -2, titleY - 2, screenW + 4, "center")
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.printf("CASINO", 2, titleY + 2, screenW, "center")
    love.graphics.setColor(1, 0.85, 0.2)
    love.graphics.printf("CASINO", 0, titleY, screenW, "center")

    -- Subtitle
    love.graphics.setFont(fonts.body or fonts.default)
    love.graphics.setColor(0.8, 0.7, 0.5, 0.8)
    love.graphics.printf("Feeling lucky, partner?", 0, titleY + 42, screenW, "center")

    -- Buttons
    local btnFont = fonts.body or fonts.default
    local subFont = fonts.default or fonts.body

    for _, r in ipairs(rects) do
        local hov = mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h

        -- Button background
        if r.id == "back" then
            love.graphics.setColor(0.15, 0.1, 0.08, hov and 0.85 or 0.6)
        else
            love.graphics.setColor(0.22, 0.14, 0.08, hov and 0.95 or 0.75)
        end
        love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 8, 8)

        -- Border
        local borderAlpha = hov and 1 or 0.5
        if r.id == "back" then
            love.graphics.setColor(0.6, 0.5, 0.35, borderAlpha)
        else
            love.graphics.setColor(0.85, 0.65, 0.2, borderAlpha)
        end
        love.graphics.setLineWidth(hov and 2.5 or 1.5)
        love.graphics.rectangle("line", r.x, r.y, r.w, r.h, 8, 8)
        love.graphics.setLineWidth(1)

        -- Shine on hover
        if hov and r.id ~= "back" then
            love.graphics.setColor(1, 0.85, 0.2, 0.08)
            love.graphics.rectangle("fill", r.x + 2, r.y + 2, r.w - 4, r.h * 0.4, 6, 6)
        end

        -- Label
        love.graphics.setFont(btnFont)
        if r.sublabel then
            local labelY = r.y + r.h * 0.22
            love.graphics.setColor(0, 0, 0, 0.7)
            love.graphics.printf(r.label, r.x + 2, labelY + 1, r.w, "center")
            love.graphics.setColor(1, 0.95, 0.75, hov and 1 or 0.85)
            love.graphics.printf(r.label, r.x, labelY, r.w, "center")
            -- Sub-label
            love.graphics.setFont(subFont)
            love.graphics.setColor(0.7, 0.65, 0.5, hov and 0.9 or 0.6)
            love.graphics.printf(r.sublabel, r.x, labelY + btnFont:getHeight() + 2, r.w, "center")
        else
            local labelY = r.y + (r.h - btnFont:getHeight()) * 0.5
            love.graphics.setColor(0, 0, 0, 0.7)
            love.graphics.printf(r.label, r.x + 1, labelY + 1, r.w, "center")
            love.graphics.setColor(0.8, 0.75, 0.6, hov and 1 or 0.7)
            love.graphics.printf(r.label, r.x, labelY, r.w, "center")
        end
    end

    -- Key hints
    love.graphics.setFont(subFont)
    love.graphics.setColor(0.5, 0.45, 0.35, 0.7)
    local hintY = rects[#rects].y + rects[#rects].h + 20
    love.graphics.printf("[1] Blackjack   [2] Roulette   [3] Slots   [ESC] Back", 0, hintY, screenW, "center")
end

local function blackjackButtonLayout(screenW, screenH, labels)
    local bw, bh = 140, 44
    local gap = 12
    local totalW = #labels * bw + (#labels - 1) * gap
    local x0 = (screenW - totalW) * 0.5
    local y = screenH * 0.76
    local rects = {}
    for i, b in ipairs(labels) do
        rects[i] = { id = b.id, label = b.label, x = x0 + (i - 1) * (bw + gap), y = y, w = bw, h = bh }
    end
    return rects
end

function drawBlackjackButtons(screenW, screenH, labels)
    local rects = blackjackButtonLayout(screenW, screenH, labels)
    for _, r in ipairs(rects) do
        local hov = hoveredBlackjackButton == r.id
        if hov then
            love.graphics.setColor(0.22, 0.14, 0.08, 0.9)
        else
            love.graphics.setColor(0.12, 0.08, 0.06, 0.75)
        end
        love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 6, 6)
        love.graphics.setColor(0.85, 0.65, 0.35, hov and 1 or 0.65)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", r.x, r.y, r.w, r.h, 6, 6)
        love.graphics.setLineWidth(1)
        love.graphics.setColor(1, 0.95, 0.82)
        love.graphics.setFont(fonts.body)
        love.graphics.printf(r.label, r.x, r.y + 12, r.w, "center")
    end
end

function hitBlackjackButton(mx, my)
    if mode ~= "blackjack" then return nil end
    local labels = nil
    if blackjackGame.state == "betting" then
        labels = {
            { id = "bet_down", label = "-" },
            { id = "bet_up", label = "+" },
            { id = "deal", label = "Deal" },
            { id = "leave", label = "Back" },
        }
    elseif blackjackGame.state == "playing" then
        labels = {
            { id = "hit", label = "Hit" },
            { id = "stand", label = "Stand" },
            { id = "double", label = "Double" },
            { id = "split", label = "Split" },
        }
    elseif blackjackGame.state == "result" then
        labels = {
            { id = "continue", label = "Continue" },
        }
    end
    if not labels then return nil end
    local rects = blackjackButtonLayout(GAME_WIDTH, GAME_HEIGHT, labels)
    for _, r in ipairs(rects) do
        if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
            return r.id
        end
    end
    return nil
end

function handleBlackjackAction(action)
    if blackjackGame.state == "betting" then
        if action == "bet_down" then
            blackjackGame:adjustWager(-blackjackGame.betStep, player.gold)
        elseif action == "bet_up" then
            blackjackGame:adjustWager(blackjackGame.betStep, player.gold)
        elseif action == "deal" then
            if blackjackGame.wager >= blackjackGame.minBet and player.gold >= blackjackGame.wager then
                local ok = player:spendGold(blackjackGame.wager, "blackjack_wager")
                if not ok then
                    message = "Not enough gold to bet that much!"
                    messageTimer = 2
                    return
                end
                blackjackGame:deal(blackjackGame.wager)
            else
                message = "Not enough gold to bet that much!"
                messageTimer = 2
            end
        elseif action == "leave" then
            mode = "main"
        end
    elseif blackjackGame.state == "playing" then
        if action == "hit" then
            blackjackGame:hit()
        elseif action == "stand" then
            blackjackGame:stand()
        elseif action == "double" then
            local cost = blackjackGame:doubleDown(player.gold)
            if cost then
                local ok = player:spendGold(cost, "blackjack_double")
                if not ok then
                    message = "Cannot double."
                    messageTimer = 1.2
                    return
                end
            else
                message = "Cannot double."
                messageTimer = 1.2
            end
        elseif action == "split" then
            local cost = blackjackGame:split(player.gold)
            if cost then
                local ok = player:spendGold(cost, "blackjack_split")
                if not ok then
                    message = "Cannot split."
                    messageTimer = 1.2
                    return
                end
            else
                message = "Cannot split."
                messageTimer = 1.2
            end
        end
    elseif blackjackGame.state == "result" then
        if action == "continue" then
            local reward = blackjackGame:getReward()
            player:addGold(reward.gold, "blackjack_reward")
            if reward.perkRarity == "rare" or reward.anyWin then
                perkOptions = Mods.Progression.rollLevelUpPerks(player, {
                    run_metadata = player and player.runMetadata or nil,
                    source = "blackjack_reward",
                })
                mode = "perk_selection"
            else
                mode = "main"
            end
        end
    end
end

function drawShop(screenW, screenH)
    local y = 100
    love.graphics.setColor(1, 0.85, 0.2)
    love.graphics.setFont(fonts.shopTitle)
    love.graphics.printf("BARTENDER", 0, y, screenW, "center")
    y = y + 50

    love.graphics.setFont(fonts.body)

    for i, item in ipairs(shop.items) do
        if item.sold then
            love.graphics.setColor(0.4, 0.4, 0.4)
            love.graphics.printf("[" .. i .. "] " .. item.name .. "  -- SOLD", 0, y, screenW, "center")
        else
            local canAfford = player.gold >= item.price
            if canAfford then
                love.graphics.setColor(0.9, 0.8, 0.6)
            else
                love.graphics.setColor(0.6, 0.4, 0.3)
            end
            love.graphics.printf("[" .. i .. "] " .. item.name .. "  $" .. item.price, 0, y, screenW, "center")
            y = y + 22
            love.graphics.setColor(0.6, 0.6, 0.6)
            local desc = item.description
            if item.type == "gear" and item.gearData then
                desc = Mods.ContentTooltips.getJoinedText("gear", item.gearData)
            elseif item.type == "weapon" and item.gunData then
                desc = Mods.ContentTooltips.getJoinedText("gun", item.gunData)
            elseif item.tooltip_key or item.tooltip_override then
                desc = Mods.ContentTooltips.getJoinedText("offer", item)
            end
            love.graphics.printf("    " .. tostring(desc or ""), 0, y, screenW, "center")
            y = y + 20
            if item.reward_reason and item.reward_reason ~= "" then
                love.graphics.setFont(fonts.default)
                love.graphics.setColor(0.65, 0.78, 0.72, 1)
                love.graphics.printf(item.reward_reason, 56, y, screenW - 112, "center")
                love.graphics.setFont(fonts.body)
                y = y + 18
            end
        end
        y = y + 35
    end

    y = y + 20
    love.graphics.setColor(0.7, 0.7, 0.7)
    love.graphics.printf(string.format("[R] Reroll  $%d   |   [ESC] Back", shop:getRerollCost()), 0, y, screenW, "center")
end

return saloon
