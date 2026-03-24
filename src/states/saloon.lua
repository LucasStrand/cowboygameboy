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

local devPanelOpen = false
local devPanelScroll = 0
local devPanelHover = nil
local devPanelRows = nil
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

local function openDevPanel()
    if not devToolsEnabled() then return end
    devPanelOpen = true
    devPanelPauseGameplay = true
    characterSheetOpen = false
    devPanelScroll = 0
    devPanelHover = nil
    devPanelRows = Mods.DevPanel.buildRows({
        gameplayPaused = devPanelPauseGameplay,
        showHitboxes = devShowHitboxes,
    })
    if not saloon.devPanelTitleFont then
        saloon.devPanelTitleFont = Mods.Font.new(16)
    end
    if not saloon.devPanelRowFont then
        saloon.devPanelRowFont = Mods.Font.new(13)
    end
    devClampScroll()
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
    if id == "toggle_dev_pause" then
        devPanelPauseGameplay = not (devPanelPauseGameplay ~= false)
        devPanelRows = Mods.DevPanel.buildRows({
            gameplayPaused = devPanelPauseGameplay,
            showHitboxes = devShowHitboxes,
        })
        devClampScroll()
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
        devPanelRows = Mods.DevPanel.buildRows({
            gameplayPaused = devPanelPauseGameplay,
            showHitboxes = devShowHitboxes,
        })
        devClampScroll()
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
    local w, h = 332, 452
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
    drawGearBlock("melee", "Melee")
    drawGearBlock("shield", "Shield")
    py = py + 22
    love.graphics.setColor(0.45, 0.45, 0.48)
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
    loadDecorSprite("wall_bar", "assets/Bar_by_Styl0o/individuals sprite/wall_bar.png")
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
    loadDecorSprite("basin", "assets/wild_west_free_pack/basin.png")
    loadDecorSprite("plant", "assets/wild_west_free_pack/plant_1.png")

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
        -- Roulette table with betting grid and wheel from the tileset
        rouletteTableQuad = love.graphics.newQuad(292, 156, 108, 64, sw, sh)
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

--- Weapon floor pickups (tap/hold interact)
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
        local mcx = monster.x + 6
        local mcy = monster.y + 8
        local mdx = pcx - mcx
        local mdy = pcy - mcy
        if (mdx * mdx + mdy * mdy) <= 35 * 35 then
            monster.drunk = true
            player:consumeMonsterEnergy()
            message = "Full heal!"
            messageTimer = 2.5
            Mods.Sfx.play("pickup_gold")
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
            npcConfig.anims = {
                {
                    name = "shuffle",
                    path = "assets/sprites/blackjack_dealer/animations/custom-Shuffles a deck of cards/south/",
                    speed = 0.3,
                    drawScale = DEALER_ACTION_DRAW_SCALE,
                },
                { name = "idle", path = "assets/sprites/blackjack_dealer/animations/breathing-idle/south/", speed = 0.3 },
            }
        elseif npcDef.type == "bartender" then
            npcConfig.promptLabel = npcDef.promptLabel or "[E] Buy Supplies"
            npcConfig.anims = {
                { name = "shaking", path = "assets/sprites/bartender/animations/shaking/south/", speed = 0.2 },
                { name = "idle", path = "assets/sprites/bartender/animations/breathing-idle/south/", speed = 0.3 },
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

    -- Monster Energy on the bar counter — reset each visit
    monster.drunk = false
    local _floorY = Mods.saloonRoom.platforms[1].y
    monster.x = 368
    monster.y = _floorY - 26
    local okM, imgM = pcall(love.graphics.newImage, "assets/monster.png")
    if okM and imgM then
        imgM:setFilter("nearest", "nearest")
        monster.img = imgM
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
    devPanelRows = Mods.DevPanel.buildRows({
        gameplayPaused = devPanelPauseGameplay,
        showHitboxes = devShowHitboxes,
    })
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
            player.effectiveAimX, player.effectiveAimY = wx, wy
            player.keyboardAimMode = false
        end

        player:update(dt, world, {})

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
            dt, pickups, player, world, weaponPickupInteractState, saloonWalkInteractConsumed
        )
        if not Mods.Keybinds.isDown("interact") then
            saloonWalkInteractConsumed = false
        end
        Mods.Combat.checkPickups(pickups, player, world)
        Mods.DamageNumbers.update(dt)
        Mods.ImpactFX.update(dt)

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
function saloon:keypressed(key)
    local _, _, _, consoleH = getDebugConsoleLayout()
    if devToolsEnabled() and devPanelOpen then
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

    if Mods.Keybinds.matches("character", key) then
        characterSheetOpen = not characterSheetOpen
        return
    end

    if mode == "walking" then
        if trySaloonWalkingInteract(key) then
            saloonWalkInteractConsumed = true
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
        if Mods.Keybinds.matches("melee", key) then
            player:meleeAttack()
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
                if hit then
                    saloonDevApplyAction(hit)
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
        if button == 1 and not player.blocking then
            local mx, my = camera:worldCoords(gx, gy, 0, 0, GAME_WIDTH, GAME_HEIGHT)
            player.aimWorldX = mx
            player.aimWorldY = my
            if player:getActiveGun() then
                local es = player:getEffectiveStats()
                local shiftShoot = love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")
                if not player.autoGun and es.meleeDamage > 0 and not shiftShoot then
                    player:meleeAttack(mx, my)
                else
                    local bulletData = player:shoot(mx, my)
                    if bulletData then
                        for _, data in ipairs(bulletData) do
                            local b = Mods.Combat.spawnBullet(world, data)
                            table.insert(bullets, b)
                        end
                    end
                end
            else
                local s = player:getEffectiveStats()
                if s.meleeDamage > 0 then
                    player:meleeAttack(mx, my)
                end
            end
        elseif button == 2 then
            player:reload()
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

    -- === LAYER 1: Background image (saloon interior walls) ===
    if bgImage then
        local viewW = screenW / CAM_ZOOM
        local viewH = screenH / CAM_ZOOM
        local bw, bh = bgImage:getDimensions()
        local scale = math.max(viewW / bw, viewH / bh)
        local camX, camY = camera:position()
        love.graphics.setColor(1, 1, 1, 0.7)
        love.graphics.draw(bgImage, camX - (bw * scale) / 2, camY - (bh * scale) / 2, 0, scale, scale)
    end

    -- === LAYER 2: Back wall from bar pack (behind everything) ===
    if decor.wall_bar then
        love.graphics.setColor(1, 1, 1, 0.5)
        local ww, wh = decor.wall_bar:getDimensions()
        -- Tile it across the room width, positioned above the floor
        local wallScale = 0.5
        local scaledH = wh * wallScale
        local wallY = floorY - scaledH
        local scaledW = ww * wallScale
        for wx = 0, roomW, scaledW do
            love.graphics.draw(decor.wall_bar, wx, wallY, 0, wallScale, wallScale)
        end
    end

    -- === LAYER 3: Decorations on the back wall ===
    -- Beam across ceiling area
    drawSprite("beam", 0, floorY - 82, 2.0, 0.7)

    -- Hanging lamps from ceiling
    drawSprite("ampule", 80, floorY - 78, 0.8, 0.8)
    drawSprite("ampule", 200, floorY - 78, 0.8, 0.8)
    drawSprite("ampule", 340, floorY - 78, 0.8, 0.8)
    drawSprite("ampule", 440, floorY - 78, 0.8, 0.8)

    -- Fridge to the left of the shelf
    drawSpriteFromBottom("fridge", 298, floorY, 1.0, 1.0)
    -- Shelf behind bar area (right side)
    drawSprite("shelf", 330, floorY - 60, 0.6, 0.5)
    -- Bottles on shelf
    drawSprite("bottles", 338, floorY - 52, 0.7, 0.7)
    drawSprite("jars", 360, floorY - 50, 0.7, 0.7)
    -- Greenboard (menu/specials)
    drawSprite("greenboard", 220, floorY - 70, 0.6, 0.6)
    -- Watch on wall
    drawSprite("watch", 400, floorY - 65, 0.6, 0.6)
    -- Wanted poster on left wall
    drawSprite("wanted", 12, floorY - 55, 0.35, 0.35)
    -- Vase decoration on dealer's table area
    drawSprite("vase", 80, floorY - 30, 0.5, 0.5)
    -- Boxes in the left corner
    drawSprite("boxes", 4, floorY - 16, 0.5, 0.5)
    -- Umbrella/coat rack near entrance
    drawSprite("umbrella", 420, floorY - 32, 0.6, 0.6)
    -- Basin near the bar
    drawSpriteFromBottom("basin", 290, floorY, 1.0, 1.0)
    -- Desert plants
    drawSpriteFromBottom("plant", 455, floorY, 0.9, 0.9)
    drawSpriteFromBottom("plant", 45, floorY, 0.8, 0.8)

    -- === LAYER 4: NPCs (behind furniture — they stand behind counter/table) ===
    for _, npc in ipairs(npcs) do
        npc:draw()
    end

    -- === LAYER 5a: Slot machine (left of dealer)
    if decor.slot_machine and slotMachineQuad then
        local smScale = 0.195
        local iw, ih = 86, 229
        local drawW = iw * smScale
        local drawH = ih * smScale
        local drawX = 4
        local drawY = floorY - drawH
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(decor.slot_machine, slotMachineQuad, drawX, drawY, 0, smScale, smScale)
    end

    -- === LAYER 5a: Roulette table in front of dealer ===
    if decor.casino_sheet and rouletteTableQuad then
        local tableScale = 0.4
        local tableW = 108 * tableScale  -- ~43px
        local tableH = 64 * tableScale   -- ~26px
        local dealerX = 140  -- dealer's x position
        local tableX = dealerX + 10 - tableW / 2  -- centered on dealer
        local woodH = 6                    -- wooden base height
        local woodTopY = floorY - woodH    -- wood panel top
        -- Wooden front panel (stays in place)
        love.graphics.setColor(0.30, 0.18, 0.08)
        love.graphics.rectangle("fill", tableX, woodTopY, tableW, woodH)
        -- Darker bottom edge
        love.graphics.setColor(0.22, 0.13, 0.06)
        love.graphics.rectangle("fill", tableX, floorY - 1, tableW, 1)
        -- Draw the green felt pushed down so it overlaps well onto the wood
        local feltY = woodTopY - tableH + 8  -- +8 pushes felt down into the wood
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(decor.casino_sheet, rouletteTableQuad, tableX, feltY, 0, tableScale, tableScale)
        -- Trim strip at the seam
        love.graphics.setColor(0.40, 0.25, 0.12)
        love.graphics.rectangle("fill", tableX, woodTopY, tableW, 1)
    end

    -- === LAYER 5b: Bar counter (foreground furniture) ===
    if decor.bar_counter then
        love.graphics.setColor(1, 1, 1)
        -- Bar counter on right side, in front of bartender
        local bw, bh = decor.bar_counter:getDimensions()
        local barScale = 0.4
        local barX = 320
        local barY = floorY - bh * barScale
        love.graphics.draw(decor.bar_counter, barX, barY, 0, barScale, barScale)
    end

    -- Stools in front of bar
    if decor.stool then
        local sw, sh = decor.stool:getDimensions()
        local stoolScale = 0.5
        for i = 0, 2 do
            drawSpriteFromBottom("stool", 325 + i * 22, floorY, stoolScale, stoolScale)
        end
    end

    -- Glass on bar counter
    drawSprite("glass", 340, floorY - 22, 0.7, 0.7)
    drawSprite("glass", 356, floorY - 22, 0.7, 0.7)

    -- Monster Energy on bar counter
    if not monster.drunk and monster.img then
        love.graphics.setColor(1, 1, 1)
        local mw, mh = monster.img:getDimensions()
        local mScale = 0.4
        love.graphics.draw(monster.img, monster.x, monster.y, 0, mScale, mScale)
    end

    -- === LAYER 6: Floor (tiled wooden planks) ===
    if decor.floor_wood then
        love.graphics.setColor(1, 1, 1)
        local fw, fh = decor.floor_wood:getDimensions()
        local tileScale = 1.0
        local tw = fw * tileScale
        local th = fh * tileScale
        -- Tile across room width, stacking 2 rows
        for tx = 0, roomW, tw do
            love.graphics.draw(decor.floor_wood, tx, floorY, 0, tileScale, tileScale)
            love.graphics.draw(decor.floor_wood, tx, floorY + th, 0, tileScale, tileScale)
        end
        -- Dark fill below the tiles
        love.graphics.setColor(0.1, 0.06, 0.03)
        love.graphics.rectangle("fill", 0, floorY + th * 2, roomW, 50)
    elseif decor.floor_bar then
        love.graphics.setColor(1, 1, 1)
        local fw, fh = decor.floor_bar:getDimensions()
        local floorScale = roomW / fw
        love.graphics.draw(decor.floor_bar, 0, floorY, 0, floorScale, floorScale)
        love.graphics.setColor(0.15, 0.1, 0.08)
        love.graphics.rectangle("fill", 0, floorY + fh * floorScale, roomW, 50)
    else
        love.graphics.setColor(0.25, 0.15, 0.08)
        love.graphics.rectangle("fill", 0, floorY, roomW, 32)
    end

    -- === LAYER 7: Exit door ===
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

        -- Exit prompt
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

    -- === LAYER 7b: Test room door ===
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

        -- Test room prompt
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

    -- === LAYER 8: Pickups (gold on the floor) ===
    for _, p in ipairs(pickups) do
        p:draw(player, camera, 0, 0, nil, pickups)
    end
    Mods.WorldInteractLabelBatch.flush()

    -- === LAYER 9: Player (in front of everything) ===
    if player then
        love.graphics.setColor(1, 1, 1)
        player:draw()
    end

    for _, b in ipairs(bullets) do
        b:draw()
    end
    Mods.ImpactFX.draw()

    Mods.DamageNumbers.draw()

    -- === LAYER 10: NPC prompts and speech (always on top in world space) ===
    for _, npc in ipairs(npcs) do
        npc:drawSpeech()
        npc:drawPrompt()
    end

    -- Monster Energy "[E] Drink" prompt
    if mode == "walking" and not monster.drunk and monster.img and player then
        local pcx = player.x + player.w / 2
        local pcy = player.y + player.h / 2
        local mcx = monster.x + 6
        local mcy = monster.y + 8
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

    -- HUD — same pipeline as game state (saloon is another map)
    Mods.HUD.draw(player)
    if not DEBUG then
        Mods.DevLog.drawOverlay(screenW, screenH)
    end
    if roomManager then
        Mods.HUD.drawRoomInfo(roomManager.currentRoomIndex, #roomManager.roomSequence)
    end
    Mods.HUD.drawDeadEye(player)

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
