--- Saloon back room: dev testing room with every world activity.
--- Reachable via a door in the saloon.
--- All activities match their real gameplay appearance and behavior.

local Gamestate      = require("lib.hump.gamestate")
local Camera         = require("lib.hump.camera")
local bump           = require("lib.bump")
local Font           = require("src.ui.font")
local Pickup         = require("src.entities.pickup")
local DamageNumbers  = require("src.ui.damage_numbers")
local Combat         = require("src.systems.combat")
local Bullet         = require("src.entities.bullet")
local ImpactFX       = require("src.systems.impact_fx")
local LabelLayout    = require("src.ui.label_layout")
local GoldCoin       = require("src.data.gold_coin")

local SlotMachine    = require("src.entities.slot_machine")
local WeaponAltar    = require("src.entities.weapon_altar")
local Shrine         = require("src.entities.shrine")
local Merchant       = require("src.entities.merchant")
local Chest          = require("src.entities.chest")
local PressurePlate  = require("src.entities.pressure_plate")
local SpikeTrap      = require("src.entities.spike_trap")
local SecretEntrance = require("src.entities.secret_entrance")

local backroom = {}

-- Room dimensions — wide enough so every activity has breathing room
local RW, RH  = 2800, 200
local FLOOR_Y = 168

-- Room geometry fed to bump
local ROOM = {
    platforms = {
        { x = 0,    y = FLOOR_Y, w = RW,  h = 32, oneWay = false },  -- main floor
        { x = 60,   y = 118,     w = 100, h = 12, oneWay = true  },  -- left raised
        { x = 2600, y = 118,     w = 120, h = 12, oneWay = true  },  -- right raised
        { x = 1200, y = 110,     w = 140, h = 12, oneWay = true  },  -- mid raised
    },
    walls = {
        { x = 0,   y = -16, w = RW,  h = 16 },
        { x = -16, y = -16, w = 16,  h = RH + 32 },
        { x = RW,  y = -16, w = 16,  h = RH + 32 },
    },
    playerSpawn = { x = 50, y = FLOOR_Y - 32 },
    exitDoor    = { x = 8,  y = FLOOR_Y - 48, w = 24, h = 48 },
}

-- Per-visit state
local player      = nil
local roomManager = nil
local world       = nil
local camera      = nil
local platforms   = {}
local walls_      = {}
local exitDoor    = nil
local pickups     = {}
local bullets     = {}
local font        = nil

-- Activities
local slotMachine    = nil
local weaponAltar    = nil
local shrines        = {}   -- all 6 blessing types
local merchant       = nil
local chestNormal    = nil
local chestRich      = nil
local chestAmbush    = nil   -- real ambush chest (bone piles, locked until cleared)
local chestFake      = nil   -- fake-ambush chest (with bone piles)
local chestTrapped   = nil   -- pressure-plate trapped chest
local chestCursed    = nil   -- cursed chest
local pressurePlates = {}
local spikeTraps     = {}
local secretEntrance = nil
local activeMerchant = nil

-- All interactable entities for focus system
local interactables  = {}
local labelLayout    = nil

--- Weapon floor pickups (tap/hold interact)
local weaponPickupInteractState = {}
local backroomInteractConsumed  = false

local doorSheet  = nil
local doorQuads  = {}
local DOOR_FRAME = 48
local CAM_ZOOM   = 3
local cam = { lerpSpeed = 5, targetX = 0, targetY = 0, currentX = 0, currentY = 0 }

---------------------------------------------------------------------------
local function loadDoor()
    if doorSheet then return end
    local ok, img = pcall(love.graphics.newImage, "assets/SaloonDoor.png")
    if not ok then return end
    img:setFilter("nearest", "nearest")
    doorSheet = img
    local sw, sh = img:getDimensions()
    for i = 0, 7 do
        doorQuads[i + 1] = love.graphics.newQuad(i * DOOR_FRAME, 0, DOOR_FRAME, DOOR_FRAME, sw, sh)
    end
end

local function spawnPickup(x, y, rtype, value)
    if rtype == "gold" then
        local specs, overflow = GoldCoin.pickupSpecsForTotal(value or 0, nil)
        if overflow > 0 and player then
            player:addGold(overflow, "backroom_pickup_gold_overflow")
        end
        for i = 1, #specs do
            local sp = specs[i]
            local p = Pickup.new(x + (i - 1) * 6, y, sp.type, sp.value)
            world:add(p, p.x, p.y, p.w, p.h)
            table.insert(pickups, p)
        end
        return
    end
    local p = Pickup.new(x, y, rtype, value)
    world:add(p, p.x, p.y, p.w, p.h)
    table.insert(pickups, p)
end

local function px() return player and (player.x + player.w * 0.5) or 0 end
local function py() return player and (player.y + player.h * 0.5) or 0 end

---------------------------------------------------------------------------
-- Focus system: determine which interactable the player would interact with
---------------------------------------------------------------------------
local focusedEntity = nil

local function updateFocus()
    focusedEntity = nil
    if not player then return end
    local ppx, ppy = px(), py()

    -- Priority order matches keypressed handler
    for _, entry in ipairs(interactables) do
        local ent = entry.entity
        if ent and ent.isNearPlayer and ent:isNearPlayer(ppx, ppy) then
            -- For chests, only focusable if closed
            if entry.type == "chest" then
                if ent.state == "closed" then
                    focusedEntity = ent
                    return
                end
            else
                focusedEntity = ent
                return
            end
        end
    end
end

---------------------------------------------------------------------------
function backroom:enter(_, _player, _roomManager)
    player      = _player
    roomManager = _roomManager

    -- Enable combat in backrooms
    player.combatDisabled = false
    player.vx = 0
    player.vy = 0

    font             = Font.new(12)
    world            = bump.newWorld(32)
    platforms        = {}
    walls_           = {}
    pickups          = {}
    weaponPickupInteractState = {}
    backroomInteractConsumed  = false
    bullets          = {}
    pressurePlates   = {}
    spikeTraps       = {}
    shrines          = {}
    interactables    = {}
    labelLayout      = LabelLayout.new()
    activeMerchant   = nil
    focusedEntity    = nil

    loadDoor()

    for _, p in ipairs(ROOM.platforms) do
        local plat = { x=p.x, y=p.y, w=p.w, h=p.h, oneWay=p.oneWay or false, isPlatform=true }
        world:add(plat, plat.x, plat.y, plat.w, plat.h)
        table.insert(platforms, plat)
    end
    for _, w in ipairs(ROOM.walls) do
        local wall = { x=w.x, y=w.y, w=w.w, h=w.h, isWall=true }
        world:add(wall, wall.x, wall.y, wall.w, wall.h)
        table.insert(walls_, wall)
    end

    local d = ROOM.exitDoor
    exitDoor = { x=d.x, y=d.y, w=d.w, h=d.h, isDoor=true }
    world:add(exitDoor, exitDoor.x, exitDoor.y, exitDoor.w, exitDoor.h)

    local sp = ROOM.playerSpawn
    player.x, player.y = sp.x, sp.y
    player.grounded        = false
    player.jumpCount       = 0
    player.coyoteTimer     = 0
    player.jumpBufferTimer = 0
    player.dashTimer       = 0
    player.dashCooldown    = 0
    world:add(player, player.x, player.y, player.w, player.h)

    camera = Camera(sp.x, sp.y)
    camera.scale = CAM_ZOOM
    cam.currentX, cam.targetX = sp.x, sp.x
    cam.currentY, cam.targetY = sp.y, sp.y

    -- ── ACTIVITIES (generously spaced across the 2800px floor) ────────────

    local nextX = 160  -- starting X, grows as we place items
    local SPACING = 150 -- minimum gap between activity centers

    -- 1. Slot machine
    slotMachine = SlotMachine.new(nextX, FLOOR_Y - 45)
    slotMachine.onResult = function(rtype, value)
        spawnPickup(slotMachine.x + slotMachine.w*0.5, slotMachine.y - 10, rtype, value)
    end
    table.insert(interactables, { entity = slotMachine, type = "slot", label = "Slot Machine" })
    nextX = nextX + SPACING

    -- 2. Weapon altar
    weaponAltar = WeaponAltar.new(nextX, FLOOR_Y - 48, roomManager and roomManager.difficulty or 1)
    weaponAltar.onChoose = function(gun)
        if gun then spawnPickup(player.x, player.y - 20, "weapon", gun) end
    end
    table.insert(interactables, { entity = weaponAltar, type = "altar", label = "Weapon Altar" })
    nextX = nextX + SPACING + 30  -- altar is wider

    -- 3. Merchant
    merchant = Merchant.new(nextX, FLOOR_Y - 48, roomManager and roomManager.difficulty or 1)
    merchant.onBuy = function(item)
        if not item then return end
        if item.type == "gun" then
            spawnPickup(merchant.x, merchant.y - 10, "weapon", item.gun)
        elseif item.type == "health" then
            spawnPickup(merchant.x, merchant.y - 10, "health", item.amount or 30)
        elseif item.type == "gold" then
            spawnPickup(merchant.x, merchant.y - 10, "gold", item.amount or 20)
        end
    end
    table.insert(interactables, { entity = merchant, type = "merchant", label = "Merchant" })
    nextX = nextX + SPACING

    -- 4. Normal chest (sprite row 0 = wooden brown)
    chestNormal = Chest.new(nextX, FLOOR_Y - 32, { tier = "normal", spriteRow = 0 })
    local normalChestX = nextX
    chestNormal.onLoot = function(loot)
        if loot then spawnPickup(normalChestX, FLOOR_Y - 40, loot.type or "gold", loot.value or 20) end
    end
    table.insert(interactables, { entity = chestNormal, type = "chest", label = "Chest" })
    nextX = nextX + SPACING

    -- 5. Rich chest (sprite row 4 = gold/ornate)
    chestRich = Chest.new(nextX, FLOOR_Y - 32, { tier = "rich" })
    local richChestX = nextX
    chestRich.onLoot = function(loot)
        if loot then spawnPickup(richChestX, FLOOR_Y - 40, loot.type or "gold", loot.value or 40) end
    end
    table.insert(interactables, { entity = chestRich, type = "chest", label = "Rich Chest" })
    nextX = nextX + SPACING

    -- 6. Real ambush chest (bone piles + skeleton ambush, opens after guards die)
    local ambushX = nextX
    local ambushFloorY = FLOOR_Y - 28
    local ambushBones = {
        { x = ambushX - 26, y = ambushFloorY, w = 18, h = 28 },
        { x = ambushX + 52, y = ambushFloorY, w = 18, h = 28 },
    }
    chestAmbush = Chest.new(ambushX, FLOOR_Y - 32, {
        tier = "normal",
        spriteRow = 2,
        bonePiles = ambushBones,
        fakeAmbush = false,
    })
    chestAmbush.onLoot = function(loot)
        if loot then spawnPickup(ambushX, FLOOR_Y - 40, loot.type or "gold", loot.value or 20) end
    end
    -- In backroom there are no enemies, so auto-kill the skeleton refs after a delay
    -- so the chest transitions from ambushing → opening naturally.
    chestAmbush.onAmbush = function(bonePiles)
        for _, bp in ipairs(bonePiles) do
            bp.riseProgress = 0
            bp._skelRef = { alive = true }  -- fake skeleton ref
        end
        -- Schedule the "skeletons" to die after 2 seconds
        chestAmbush._ambushTimer = 2.0
    end
    table.insert(interactables, { entity = chestAmbush, type = "chest", label = "Ambush Chest" })
    nextX = nextX + SPACING

    -- 7. Fake-ambush chest (dark chest row 2 + bone piles, no real skeletons)
    local fakeX = nextX
    local fakeFloorY = FLOOR_Y - 28
    local bonePiles = {
        { x = fakeX - 26, y = fakeFloorY, w = 18, h = 28, fake = true },
        { x = fakeX + 52, y = fakeFloorY, w = 18, h = 28, fake = true },
    }
    chestFake = Chest.new(fakeX, FLOOR_Y - 32, {
        tier = "normal",
        spriteRow = 2,
        bonePiles = bonePiles,
        fakeAmbush = true,
    })
    chestFake.onLoot = function(loot)
        if loot then spawnPickup(fakeX, FLOOR_Y - 40, loot.type or "gold", loot.value or 20) end
    end
    table.insert(interactables, { entity = chestFake, type = "chest", label = "Fake Ambush" })
    nextX = nextX + SPACING

    -- 8. Cursed chest (damages on open, red glow)
    local cursedX = nextX
    chestCursed = Chest.new(cursedX, FLOOR_Y - 32, { tier = "cursed" })
    chestCursed.onLoot = function(loot)
        if loot then spawnPickup(cursedX, FLOOR_Y - 40, loot.type or "gold", loot.value or 20) end
    end
    table.insert(interactables, { entity = chestCursed, type = "chest", label = "Cursed Chest" })
    nextX = nextX + SPACING

    -- 9. Trapped chest (120px zone: plate-gap-chest-gap-plate, matches map_activities)
    local trapZoneX = nextX
    local chestTX = trapZoneX + 36  -- chest in center of 120px zone
    chestTrapped = Chest.new(chestTX, FLOOR_Y - 32, { tier = "rich" })
    chestTrapped.onLoot = function(loot)
        if loot then spawnPickup(chestTX, FLOOR_Y - 40, loot.type or "gold", loot.value or 20) end
    end
    -- Spike traps flush with platform surface
    local trapY = FLOOR_Y - 4
    local trap1 = SpikeTrap.new(trapZoneX,      trapY, 28)
    local trap2 = SpikeTrap.new(trapZoneX + 92, trapY, 28)
    table.insert(spikeTraps, trap1)
    table.insert(spikeTraps, trap2)
    -- Pressure plates on both sides, stepping on either fires both traps
    local plateY = FLOOR_Y - 5
    local plate1 = PressurePlate.new(trapZoneX,      plateY, { trap1, trap2 })
    local plate2 = PressurePlate.new(trapZoneX + 92, plateY, { trap1, trap2 })
    table.insert(pressurePlates, plate1)
    table.insert(pressurePlates, plate2)
    table.insert(interactables, { entity = chestTrapped, type = "chest", label = "Trapped Chest" })
    nextX = nextX + SPACING + 30

    -- 10. All 6 shrine types
    local BLESSINGS = {
        { idx = 1, name = "Regen" },
        { idx = 2, name = "Sharpshooter" },
        { idx = 3, name = "Ironhide" },
        { idx = 4, name = "Swiftness" },
        { idx = 5, name = "Fortune" },
        { idx = 6, name = "Wisdom" },
    }
    for _, b in ipairs(BLESSINGS) do
        local s = Shrine.new(nextX, FLOOR_Y - 48, { blessing = b.idx })
        s.onActivate = function(buffId)
            if player and buffId then
                local Buffs = require("src.systems.buffs")
                Buffs.apply(player, buffId, 1)
            end
        end
        table.insert(shrines, s)
        table.insert(interactables, { entity = s, type = "shrine", label = "Shrine: " .. b.name })
        nextX = nextX + 90  -- shrines are narrow, 90px apart is fine
    end
    nextX = nextX + 60  -- extra gap after shrine row

    -- 11. Secret entrance (right end)
    secretEntrance = SecretEntrance.new(nextX, FLOOR_Y - 80, 14, 80)
    nextX = nextX + SPACING

    -- Wild pickups on raised platforms
    spawnPickup(75,  FLOOR_Y - 50, "gold",   15)
    spawnPickup(110, FLOOR_Y - 50, "health", 10)
    spawnPickup(1230, 80,          "gold",   25)
    spawnPickup(1270, 80,          "xp",     20)
end

---------------------------------------------------------------------------
function backroom:leave()
    if world and player and world:hasItem(player) then world:remove(player) end
    -- Clean up bullets from bump world
    for _, b in ipairs(bullets) do
        if world and world:hasItem(b) then world:remove(b) end
    end
    player.combatDisabled = false
    world          = nil
    camera         = nil
    pickups        = {}
    bullets        = {}
    pressurePlates = {}
    spikeTraps     = {}
    shrines        = {}
    interactables  = {}
    slotMachine    = nil
    weaponAltar    = nil
    merchant       = nil
    chestNormal    = nil
    chestRich      = nil
    chestAmbush    = nil
    chestFake      = nil
    chestCursed    = nil
    chestTrapped   = nil
    secretEntrance = nil
    activeMerchant = nil
    focusedEntity  = nil
end

---------------------------------------------------------------------------
local function isNearDoor()
    local dcx = exitDoor.x + exitDoor.w * 0.5
    local dcy = exitDoor.y + exitDoor.h * 0.5
    return (px()-dcx)^2 + (py()-dcy)^2 < 50*50
end

local function allChests()
    local list = {}
    if chestNormal  then list[#list+1] = chestNormal end
    if chestRich    then list[#list+1] = chestRich end
    if chestAmbush  then list[#list+1] = chestAmbush end
    if chestFake    then list[#list+1] = chestFake end
    if chestCursed  then list[#list+1] = chestCursed end
    if chestTrapped then list[#list+1] = chestTrapped end
    return list
end

local function tryBackroomWorldInteract(key)
    local Keybinds = require("src.systems.keybinds")
    if not (Keybinds.matches("interact", key) or key == "e") then return false end
    if isNearDoor() then
        Gamestate.switch(require("src.states.saloon"), player, roomManager)
        return true
    end
    if slotMachine and slotMachine:isNearPlayer(px(), py()) then
        slotMachine:tryPlay(player)
        return true
    end
    if weaponAltar and weaponAltar:isNearPlayer(px(), py()) then
        weaponAltar:tryChoose(player)
        return true
    end
    for _, s in ipairs(shrines) do
        if s:isNearPlayer(px(), py()) then
            s:tryActivate(player)
            return true
        end
    end
    if merchant and merchant:isNearPlayer(px(), py()) then
        if merchant:tryInteract() then activeMerchant = merchant end
        return true
    end
    for _, ch in ipairs(allChests()) do
        if ch and ch:isNearPlayer(px(), py()) then
            ch:tryOpen(player, function(dmg)
                if dmg and dmg > 0 then
                    local ok, d = player:takeDamage(dmg)
                    if ok then DamageNumbers.spawn(px(), player.y, d, "in") end
                end
            end)
            return true
        end
    end
    return false
end

function backroom:keypressed(key)
    if not player then return end
    local Keybinds = require("src.systems.keybinds")

    if activeMerchant then
        local result = activeMerchant:handleKey(key, player)
        if result then activeMerchant = nil end
        return
    end

    if tryBackroomWorldInteract(key) then
        backroomInteractConsumed = true
    end

    if Keybinds.matches("jump", key) or key == "w" or key == "up" then player:jump() end
    if Keybinds.matches("drop", key) or key == "down" then player:tryDropThrough() end
end

function backroom:keyreleased(key)
    if player and player.keyreleased then player:keyreleased(key) end
end

---------------------------------------------------------------------------
-- Mouse: shooting
---------------------------------------------------------------------------
function backroom:mousepressed(gx, gy, button)
    if not player or not camera or not world then return end

    if button == 1 and not player.blocking then
        local sw, sh = love.graphics.getDimensions()
        local mx, my = camera:worldCoords(gx, gy, 0, 0, sw, sh)
        player.aimWorldX = mx
        player.aimWorldY = my
        if player:getActiveGun() then
            local bulletData = player:shoot(mx, my)
            if bulletData then
                for _, data in ipairs(bulletData) do
                    local b = Combat.spawnBullet(world, data)
                    table.insert(bullets, b)
                end
            end
        end
    end
    if button == 2 then
        local wasReloading = player.reloading
        player:reload()
    end
end

---------------------------------------------------------------------------
function backroom:update(dt)
    if not player or not world then return end

    -- Update aim position for player (mouse world coords)
    if camera then
        local mgx, mgy = love.mouse.getPosition()
        local sw, sh = love.graphics.getDimensions()
        local wmx, wmy = camera:worldCoords(mgx, mgy, 0, 0, sw, sh)
        player.aimWorldX = wmx
        player.aimWorldY = wmy
    end

    player:update(dt, world, {})

    if player.x < 0 then player.x = 0 end
    if player.x + player.w > RW then player.x = RW - player.w end

    -- Bullets
    Combat.updateBullets(bullets, dt, world, {}, player)
    -- Clean dead bullets
    local i = #bullets
    while i >= 1 do
        if not bullets[i].alive then
            if world:hasItem(bullets[i]) then world:remove(bullets[i]) end
            table.remove(bullets, i)
        end
        i = i - 1
    end

    -- Activities
    if slotMachine    then slotMachine:update(dt) end
    if weaponAltar    then weaponAltar:update(dt, player) end
    for _, s in ipairs(shrines) do s:update(dt) end
    if merchant       then merchant:update(dt) end
    for _, ch in ipairs(allChests()) do
        if ch then
            ch:update(dt)
            -- Backroom ambush timer: auto-kill fake skeleton refs so chest opens
            if ch._ambushTimer then
                ch._ambushTimer = ch._ambushTimer - dt
                -- Animate bone pile rise
                for _, bp in ipairs(ch.bonePiles or {}) do
                    if bp._skelRef and bp._skelRef.alive then
                        bp.riseProgress = math.min(1, (bp.riseProgress or 0) + dt * 1.5)
                    end
                end
                if ch._ambushTimer <= 0 then
                    for _, bp in ipairs(ch.bonePiles or {}) do
                        if bp._skelRef then bp._skelRef.alive = false end
                    end
                    ch._ambushTimer = nil
                end
            end
        end
    end
    for _, pp in ipairs(pressurePlates) do pp:update(dt, player) end
    for _, st in ipairs(spikeTraps)     do st:update(dt, player) end
    if secretEntrance then secretEntrance:update(dt, player) end

    -- Pickups
    for j = #pickups, 1, -1 do
        local p = pickups[j]
        p:update(dt, world, player.x + player.w*0.5, player.y + player.h*0.5)
        if not p.alive then
            if world:hasItem(p) then world:remove(p) end
            table.remove(pickups, j)
        end
    end
    local Keybinds = require("src.systems.keybinds")
    weaponPickupInteractState = Combat.advanceWeaponPickupInteraction(
        dt, pickups, player, world, weaponPickupInteractState, backroomInteractConsumed
    )
    if not Keybinds.isDown("interact") then
        backroomInteractConsumed = false
    end
    Combat.checkPickups(pickups, player, world)

    DamageNumbers.update(dt)
    ImpactFX.update(dt)

    -- Focus system
    updateFocus()

    -- Camera
    local sw, sh = love.graphics.getDimensions()
    local viewW, viewH = sw / CAM_ZOOM, sh / CAM_ZOOM
    cam.targetX = math.max(viewW*0.5, math.min(RW - viewW*0.5, px()))
    cam.targetY = math.max(viewH*0.5, math.min(RH - viewH*0.5, py()))
    local t = 1 - math.exp(-cam.lerpSpeed * dt)
    cam.currentX = cam.currentX + (cam.targetX - cam.currentX) * t
    cam.currentY = cam.currentY + (cam.targetY - cam.currentY) * t
    camera:lookAt(cam.currentX, cam.currentY)
end

---------------------------------------------------------------------------
function backroom:draw()
    if not camera then return end
    local sw, sh = love.graphics.getDimensions()

    love.graphics.setColor(0.12, 0.08, 0.05)
    love.graphics.rectangle("fill", 0, 0, sw, sh)

    camera:attach()

    -- Platforms
    for _, p in ipairs(platforms) do
        love.graphics.setColor(0.28, 0.18, 0.10)
        love.graphics.rectangle("fill", p.x, p.y, p.w, p.h)
        love.graphics.setColor(0.42, 0.28, 0.14)
        love.graphics.rectangle("fill", p.x, p.y, p.w, 3)
    end

    -- Helper: is this entity the focused one?
    local function isFocused(ent)
        return focusedEntity == ent
    end

    -- Helper: set alpha for focused/unfocused state
    -- Returns the alpha multiplier to use
    local function getFocusAlpha(ent)
        if focusedEntity == nil then return 1.0 end
        if focusedEntity == ent then return 1.0 end
        -- Check if this entity is near the player (could be competing)
        if ent and ent.isNearPlayer and ent:isNearPlayer(px(), py()) then
            return 0.35  -- unfocused but nearby
        end
        return 1.0  -- not nearby, full alpha
    end

    -- Activities (back to front)
    if secretEntrance then secretEntrance:draw() end
    for _, st in ipairs(spikeTraps)     do st:draw() end
    for _, pp in ipairs(pressurePlates) do pp:draw() end

    for _, ch in ipairs(allChests()) do
        if ch then
            local alpha = getFocusAlpha(ch)
            if alpha < 1.0 then
                love.graphics.setColor(1, 1, 1, alpha)
            end
            ch:draw(player, isFocused(ch) and ch:isNearPlayer(px(), py()))
            if alpha < 1.0 then
                love.graphics.setColor(1, 1, 1, 1)
            end
        end
    end

    for _, s in ipairs(shrines) do
        local alpha = getFocusAlpha(s)
        if alpha < 1.0 then
            love.graphics.setColor(1, 1, 1, alpha)
        end
        s:draw(isFocused(s) and s:isNearPlayer(px(), py()))
        if alpha < 1.0 then
            love.graphics.setColor(1, 1, 1, 1)
        end
    end

    if merchant then
        local alpha = getFocusAlpha(merchant)
        if alpha < 1.0 then
            love.graphics.setColor(1, 1, 1, alpha)
        end
        merchant:draw(isFocused(merchant) and merchant:isNearPlayer(px(), py()), player.gold)
        if alpha < 1.0 then
            love.graphics.setColor(1, 1, 1, 1)
        end
    end

    if weaponAltar then
        local alpha = getFocusAlpha(weaponAltar)
        if alpha < 1.0 then
            love.graphics.setColor(1, 1, 1, alpha)
        end
        weaponAltar:updateSelection(px(), py())
        weaponAltar:draw(isFocused(weaponAltar) and weaponAltar:isNearPlayer(px(), py()))
        if alpha < 1.0 then
            love.graphics.setColor(1, 1, 1, 1)
        end
    end

    if slotMachine then
        local alpha = getFocusAlpha(slotMachine)
        if alpha < 1.0 then
            love.graphics.setColor(1, 1, 1, alpha)
        end
        slotMachine:draw(isFocused(slotMachine) and slotMachine:isNearPlayer(px(), py()))
        if alpha < 1.0 then
            love.graphics.setColor(1, 1, 1, 1)
        end
    end

    for _, p in ipairs(pickups) do p:draw() end

    -- Bullets
    for _, b in ipairs(bullets) do b:draw() end

    player:draw()

    -- Exit door
    if doorSheet and #doorQuads > 0 then
        love.graphics.setColor(1, 1, 1)
        local scale = exitDoor.h / DOOR_FRAME
        local drawX = exitDoor.x + exitDoor.w*0.5 - (DOOR_FRAME*scale)*0.5
        local drawY = exitDoor.y + exitDoor.h - DOOR_FRAME*scale
        love.graphics.draw(doorSheet, doorQuads[8], drawX, drawY, 0, scale, scale)
    else
        love.graphics.setColor(0.4, 0.25, 0.1)
        love.graphics.rectangle("fill", exitDoor.x, exitDoor.y, exitDoor.w, exitDoor.h)
    end
    if isNearDoor() then
        local label = "[E] Back to Saloon"
        local f = font or love.graphics.getFont()
        local tw = f:getWidth(label)
        local dcx = exitDoor.x + exitDoor.w*0.5
        love.graphics.setFont(f)
        love.graphics.setColor(0,0,0,0.7)
        love.graphics.print(label, math.floor(dcx - tw*0.5)+1, exitDoor.y-15)
        love.graphics.setColor(1,0.9,0.5)
        love.graphics.print(label, math.floor(dcx - tw*0.5),   exitDoor.y-16)
    end

    -- Labels with collision avoidance (LabelLayout prevents overlap)
    if font then love.graphics.setFont(font) end
    labelLayout:reset()
    local f = font or love.graphics.getFont()

    local function lbl(cx, baseY, text, ent)
        local alpha = 1.0
        if focusedEntity and ent then
            if focusedEntity ~= ent and ent.isNearPlayer and ent:isNearPlayer(px(), py()) then
                alpha = 0.3
            end
        end
        local y = labelLayout:add(cx, baseY, text, f)
        local tw = f:getWidth(text)
        love.graphics.setColor(0, 0, 0, 0.6 * alpha)
        love.graphics.print(text, math.floor(cx - tw*0.5)+1, y+1)
        love.graphics.setColor(1, 0.85, 0.4, alpha)
        love.graphics.print(text, math.floor(cx - tw*0.5),   y)
    end

    if slotMachine then lbl(slotMachine.x + slotMachine.w*0.5, slotMachine.y - 20, "Slot Machine", slotMachine) end
    -- Reserve space for weapon altar's own internal labels so backroom label avoids them
    if weaponAltar then
        -- The altar draws "Choose a weapon" at y - 28 and gun names at y + h + 2
        if weaponAltar.state == "choosing" then
            labelLayout:add(weaponAltar.x + 56, weaponAltar.y - 28, "Choose a weapon", f)
        end
        for i = 1, 3 do
            if weaponAltar.choices and weaponAltar.choices[i] then
                local pcx = weaponAltar:pedestalCenterX(i)
                labelLayout:add(pcx, weaponAltar.y + weaponAltar.h + 2, weaponAltar.choices[i].name, f)
            end
        end
        lbl(weaponAltar.x + 56, weaponAltar.y - 16, "Weapon Altar", weaponAltar)
    end
    if merchant    then lbl(merchant.x + merchant.w*0.5, merchant.y - 16, "Merchant", merchant) end
    if chestNormal then lbl(chestNormal.x + 24, chestNormal.y - 16, "Chest", chestNormal) end
    if chestRich   then lbl(chestRich.x   + 24, chestRich.y   - 16, "Rich Chest", chestRich) end
    if chestAmbush then lbl(chestAmbush.x + 24, chestAmbush.y - 16, "Ambush Chest", chestAmbush) end
    if chestFake   then lbl(chestFake.x   + 24, chestFake.y   - 16, "Fake Ambush", chestFake) end
    if chestCursed then lbl(chestCursed.x + 24, chestCursed.y - 16, "Cursed Chest", chestCursed) end
    if chestTrapped then lbl(chestTrapped.x + 24, chestTrapped.y - 16, "Trapped Chest", chestTrapped) end
    if #pressurePlates >= 2 then
        local ppCx = (pressurePlates[1].x + pressurePlates[2].x + 28) * 0.5
        lbl(ppCx, FLOOR_Y - 42, "Pressure Plates")
    end
    for i, s in ipairs(shrines) do
        local names = { "Regen", "Sharpshooter", "Ironhide", "Swiftness", "Fortune", "Wisdom" }
        lbl(s.x + s.w*0.5, s.y - 16, names[i] or "Shrine", s)
    end
    if secretEntrance then lbl(secretEntrance.x + 7, secretEntrance.y - 16, "Secret Wall", secretEntrance) end

    camera:detach()

    -- Merchant shop UI (screen-space)
    if activeMerchant then
        activeMerchant:drawShopUI(sw*0.5, sh - 8, player.gold)
    end

    -- Impact FX (screen-space compatible)
    ImpactFX.draw()

    if font then love.graphics.setFont(font) end
    love.graphics.setColor(0.6,0.5,0.3,0.7)
    love.graphics.printf("~ Back Room ~  (all world activities)", 0, 8, sw, "center")

    DamageNumbers.draw()
end

return backroom
