local Gamestate = require("lib.hump.gamestate")
local Camera = require("lib.hump.camera")
local bump = require("lib.bump")

local Font = require("src.ui.font")
local Blackjack = require("src.systems.blackjack")
local Roulette = require("src.systems.roulette")
local Shop = require("src.systems.shop")
local PerkCard = require("src.ui.perk_card")
local Cursor = require("src.ui.cursor")
local Keybinds = require("src.systems.keybinds")
local NPC = require("src.entities.npc")

local saloonRoom = require("src.data.saloon_room")

local saloon = {}

-- Persistent assets (loaded once)
local bgImage = nil
local doorSheet = nil
local doorQuads = {}
local DOOR_FRAME_SIZE = 48

-- Bar decoration sprites (loaded once)
local decor = {}
local rouletteTableQuad = nil

-- Per-visit state
local player = nil
local roomManager = nil
local world = nil
local camera = nil
local npcs = {}
local platforms = {}
local walls = {}
local exitDoor = nil
local difficulty = 1

local mode = "walking"  -- walking | blackjack | roulette | casino_menu | shop | perk_selection
local blackjackGame = nil
local rouletteGame = nil
local shop = nil
local message = ""
local messageTimer = 0
local perkOptions = nil
local hoveredPerk = nil
local fonts = {}

local CAM_ZOOM = 3

local nearbyNPC = nil  -- NPC currently in interact range

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

    -- Casino tileset (roulette table)
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
    player.combatDisabled = false
    Gamestate.pop()
end

local function findNearbyNPC()
    for _, npc in ipairs(npcs) do
        if npc:canInteract(player.x, player.y, player.w, player.h) then
            return npc
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- State callbacks
---------------------------------------------------------------------------
function saloon:enter(_, _player, _roomManager)
    player = _player
    roomManager = _roomManager
    difficulty = _roomManager and _roomManager.difficulty or 1

    -- Disable combat
    player.combatDisabled = true
    player.vx = 0
    player.vy = 0

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
    fonts.title = Font.new(36)
    fonts.stat = Font.new(18)
    fonts.body = Font.new(16)
    fonts.card = Font.new(20)
    fonts.shopTitle = Font.new(24)
    fonts.default = Font.new(12)
    fonts.hud = Font.new(14)
    Cursor.setDefault()

    -- Create bump world
    world = bump.newWorld(32)

    -- Add platforms (only floor — bar counter is decorative only)
    platforms = {}
    for _, p in ipairs(saloonRoom.platforms) do
        local plat = { x = p.x, y = p.y, w = p.w, h = p.h, oneWay = p.oneWay or false, isPlatform = true }
        world:add(plat, plat.x, plat.y, plat.w, plat.h)
        table.insert(platforms, plat)
    end

    -- Add walls
    walls = {}
    for _, w in ipairs(saloonRoom.walls) do
        local wall = { x = w.x, y = w.y, w = w.w, h = w.h, isWall = true }
        world:add(wall, wall.x, wall.y, wall.w, wall.h)
        table.insert(walls, wall)
    end

    -- Add exit door (collision zone, passthrough)
    local d = saloonRoom.exitDoor
    exitDoor = { x = d.x, y = d.y, w = d.w, h = d.h, isDoor = true }
    world:add(exitDoor, exitDoor.x, exitDoor.y, exitDoor.w, exitDoor.h)

    -- Spawn NPCs — NO collision bodies, player walks freely in front of them
    npcs = {}
    for _, npcDef in ipairs(saloonRoom.npcs) do
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

        local npc = NPC.new(npcConfig)
        -- NOT added to bump world — NPCs are decorative, player walks in front
        table.insert(npcs, npc)
    end

    -- Position player at spawn
    local sp = saloonRoom.playerSpawn
    player.x = sp.x
    player.y = sp.y
    player.grounded = false
    player.jumpCount = 0
    player.coyoteTimer = 0
    player.jumpBufferTimer = 0
    player.dashTimer = 0
    player.dashCooldown = 0
    world:add(player, player.x, player.y, player.w, player.h)

    -- Camera
    camera = Camera(saloonRoom.width / 2, saloonRoom.height / 2)
    camera.scale = CAM_ZOOM

    -- Game systems
    blackjackGame = Blackjack.new()
    rouletteGame = Roulette.new()
    shop = Shop.new(difficulty)

    mode = "walking"
    message = ""
    messageTimer = 0
    perkOptions = nil
    hoveredPerk = nil
    nearbyNPC = nil
end

function saloon:leave()
    if world and player then
        pcall(function() world:remove(player) end)
    end
    player.combatDisabled = false
end

---------------------------------------------------------------------------
-- Update
---------------------------------------------------------------------------
function saloon:update(dt)
    if messageTimer > 0 then
        messageTimer = messageTimer - dt
    end

    if mode == "walking" then
        player:update(dt, world, {})

        -- Clamp player to room bounds
        if player.x < 0 then player.x = 0 end
        if player.x + player.w > saloonRoom.width then
            player.x = saloonRoom.width - player.w
        end

        -- Camera (static — room fits in view)
        camera:lockPosition(saloonRoom.width / 2, saloonRoom.height / 2)

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
        hoveredPerk = PerkCard.getHovered(perkOptions, mx, my)
    elseif mode == "blackjack" then
        local mx, my = windowToGame(love.mouse.getPosition())
        blackjackGame:updateHover(mx, my, GAME_WIDTH, GAME_HEIGHT)
    elseif mode == "roulette" then
        rouletteGame:update(dt, player)
    end
end

---------------------------------------------------------------------------
-- Input
---------------------------------------------------------------------------
function saloon:keypressed(key)
    if mode == "walking" then
        if Keybinds.matches("interact", key) then
            if nearbyNPC then
                if nearbyNPC.type == "dealer" then
                    mode = "casino_menu"
                elseif nearbyNPC.type == "bartender" then
                    mode = "shop"
                end
                return
            end
            -- Check if near exit door
            local pcx = player.x + player.w / 2
            local pcy = player.y + player.h / 2
            local dcx = exitDoor.x + exitDoor.w / 2
            local dcy = exitDoor.y + exitDoor.h / 2
            local dx = pcx - dcx
            local dy = pcy - dcy
            if dx * dx + dy * dy < 50 * 50 then
                continueGame()
                return
            end
        end

        if Keybinds.matches("jump", key) or key == "w" or key == "up" then
            player:jump()
        end
        if Keybinds.matches("drop", key) or key == "down" then
            player:tryDropThrough()
        end

    elseif mode == "casino_menu" then
        if key == "1" then
            applyOutcome(blackjackGame:enterTable(player.gold))
        elseif key == "2" then
            applyOutcome(rouletteGame:enterTable(player.gold))
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

    elseif mode == "shop" then
        local num = tonumber(key)
        if num and num >= 1 and num <= #shop.items then
            local success, msg = shop:buyItem(num, player)
            message = msg
            messageTimer = 2
        elseif key == "escape" or key == "backspace" then
            mode = "walking"
        end

    elseif mode == "perk_selection" then
        local num = tonumber(key)
        if num and num >= 1 and num <= #perkOptions then
            player:applyPerk(perkOptions[num])
            local nextMode = blackjackGame:completePerkSelection()
            mode = (nextMode == "main") and "walking" or nextMode
            perkOptions = nil
        end
    end
end

function saloon:mousepressed(x, y, button)
    if mode == "perk_selection" and button == 1 and hoveredPerk then
        player:applyPerk(perkOptions[hoveredPerk])
        local nextMode = blackjackGame:completePerkSelection()
        mode = (nextMode == "main") and "walking" or nextMode
        perkOptions = nil
        return
    end
    if mode == "blackjack" then
        local mx, my = windowToGame(x, y)
        applyOutcome(blackjackGame:handleMousePressed(mx, my, button, GAME_WIDTH, GAME_HEIGHT, player))
    elseif mode == "roulette" then
        local mx, my = windowToGame(x, y)
        applyOutcome(rouletteGame:handleMousePressed(mx, my, button, GAME_WIDTH, GAME_HEIGHT, player))
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
    local roomW = saloonRoom.width
    local floorY = saloonRoom.platforms[1].y  -- top of floor

    -- Dark background
    love.graphics.setColor(0.08, 0.05, 0.03)
    love.graphics.rectangle("fill", 0, 0, screenW, screenH)

    camera:attach(0, 0, screenW, screenH)

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
    drawSprite("beam", 0, floorY - 82, 1.3, 0.7)

    -- Hanging lamps from ceiling
    drawSprite("ampule", 70, floorY - 78, 0.8, 0.8)
    drawSprite("ampule", 160, floorY - 78, 0.8, 0.8)
    drawSprite("ampule", 250, floorY - 78, 0.8, 0.8)

    -- Fridge to the left of the shelf
    drawSpriteFromBottom("fridge", 178, floorY, 1.0, 1.0)
    -- Shelf behind bar area (right side)
    drawSprite("shelf", 210, floorY - 60, 0.6, 0.5)
    -- Bottles on shelf
    drawSprite("bottles", 218, floorY - 52, 0.7, 0.7)
    drawSprite("jars", 240, floorY - 50, 0.7, 0.7)
    -- Greenboard (menu/specials)
    drawSprite("greenboard", 140, floorY - 70, 0.6, 0.6)
    -- Watch on wall
    drawSprite("watch", 280, floorY - 65, 0.6, 0.6)
    -- Wanted poster on left wall
    drawSprite("wanted", 12, floorY - 55, 0.35, 0.35)
    -- Vase decoration on dealer's table area
    drawSprite("vase", 60, floorY - 30, 0.5, 0.5)
    -- Boxes in the left corner
    drawSprite("boxes", 4, floorY - 16, 0.5, 0.5)
    -- Umbrella/coat rack near entrance
    drawSprite("umbrella", 290, floorY - 32, 0.6, 0.6)

    -- === LAYER 4: NPCs (behind furniture — they stand behind counter/table) ===
    for _, npc in ipairs(npcs) do
        npc:draw()
    end

    -- === LAYER 5a: Roulette table in front of dealer ===
    if decor.casino_sheet and rouletteTableQuad then
        local tableScale = 0.4
        local tableW = 108 * tableScale  -- ~43px
        local tableH = 64 * tableScale   -- ~26px
        local dealerX = 100  -- dealer's x position
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
        local barX = 200
        local barY = floorY - bh * barScale
        love.graphics.draw(decor.bar_counter, barX, barY, 0, barScale, barScale)
    end

    -- Stools in front of bar
    if decor.stool then
        local sw, sh = decor.stool:getDimensions()
        local stoolScale = 0.5
        for i = 0, 2 do
            drawSpriteFromBottom("stool", 205 + i * 22, floorY, stoolScale, stoolScale)
        end
    end

    -- Glass on bar counter
    drawSprite("glass", 220, floorY - 22, 0.7, 0.7)
    drawSprite("glass", 236, floorY - 22, 0.7, 0.7)

    -- === LAYER 6: Floor ===
    if decor.floor_bar then
        love.graphics.setColor(1, 1, 1)
        local fw, fh = decor.floor_bar:getDimensions()
        -- Scale floor to fill room width, positioned at floor level
        local floorScale = roomW / fw
        local floorDrawH = fh * floorScale
        love.graphics.draw(decor.floor_bar, 0, floorY, 0, floorScale, floorScale)
        -- Fill below floor edge if needed
        love.graphics.setColor(0.15, 0.1, 0.08)
        love.graphics.rectangle("fill", 0, floorY + floorDrawH, roomW, 50)
    else
        -- Fallback floor
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

    -- === LAYER 8: Player (in front of everything) ===
    if player then
        love.graphics.setColor(1, 1, 1)
        player:draw()
    end

    -- === LAYER 9: NPC prompts (always on top in world space) ===
    for _, npc in ipairs(npcs) do
        npc:drawPrompt()
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
            rouletteGame:draw(screenW, screenH, fonts)
        elseif mode == "shop" then
            drawShop(screenW, screenH)
        elseif mode == "perk_selection" then
            PerkCard.draw(perkOptions, nil, hoveredPerk)
        end
    end

    -- HUD bar
    drawSaloonHUD(screenW, screenH)

    -- Message toast
    if messageTimer > 0 then
        love.graphics.setFont(fonts.body)
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.printf(message, 1, screenH - 49, screenW, "center")
        love.graphics.setColor(1, 1, 0.5)
        love.graphics.printf(message, 0, screenH - 50, screenW, "center")
    end

    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(fonts.default)
end

---------------------------------------------------------------------------
-- Sub-draw functions
---------------------------------------------------------------------------
function drawSaloonHUD(screenW, screenH)
    love.graphics.setFont(fonts.hud)
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.rectangle("fill", 0, 0, screenW, 28)

    local stats = player:getEffectiveStats()
    local text = "Gold: $" .. player.gold .. "    HP: " .. player.hp .. "/" .. stats.maxHP .. "    Level: " .. player.level
    love.graphics.setColor(1, 0.85, 0.2)
    love.graphics.printf(text, 10, 6, screenW - 20, "left")

    love.graphics.setColor(0.8, 0.65, 0.35)
    love.graphics.printf("SALOON", 0, 6, screenW - 10, "right")
end

function drawCasinoMenu(screenW, screenH)
    local y = screenH * 0.30
    love.graphics.setColor(1, 0.85, 0.2)
    love.graphics.setFont(fonts.shopTitle or fonts.title)
    love.graphics.printf("CASINO", 0, y, screenW, "center")
    y = y + 50
    love.graphics.setFont(fonts.body)
    love.graphics.setColor(0.9, 0.8, 0.6)
    love.graphics.printf("[1] Blackjack", 0, y, screenW, "center")
    y = y + 40
    love.graphics.printf("[2] Roulette", 0, y, screenW, "center")
    y = y + 60
    love.graphics.setColor(0.7, 0.7, 0.7)
    love.graphics.printf("[ESC] Back", 0, y, screenW, "center")
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
            love.graphics.printf("[" .. i .. "] " .. item.name .. "  ($" .. item.price .. ")", 0, y, screenW, "center")
            y = y + 22
            love.graphics.setColor(0.6, 0.6, 0.6)
            love.graphics.printf("    " .. item.description, 0, y, screenW, "center")
        end
        y = y + 35
    end

    y = y + 20
    love.graphics.setColor(0.7, 0.7, 0.7)
    love.graphics.printf("[ESC] Back", 0, y, screenW, "center")
end

return saloon
