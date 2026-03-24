--- Saloon back room: a testing room reachable via a door in the saloon.
--- Contains one of every world activity so you can test them without
--- running through combat rooms to find them.

local Gamestate  = require("lib.hump.gamestate")
local Camera     = require("lib.hump.camera")
local bump       = require("lib.bump")
local Font       = require("src.ui.font")
local Pickup     = require("src.entities.pickup")
local DamageNumbers = require("src.ui.damage_numbers")

local SlotMachine   = require("src.entities.slot_machine")
local WeaponAltar   = require("src.entities.weapon_altar")
local Shrine        = require("src.entities.shrine")
local PressurePlate = require("src.entities.pressure_plate")
local SpikeTrap     = require("src.entities.spike_trap")
local SecretEntrance= require("src.entities.secret_entrance")

local backroom = {}

-- Room dimensions
local RW, RH = 640, 200

-- Layout
local FLOOR_Y    = 168
local ROOM = {
    platforms = {
        { x = 0,   y = FLOOR_Y, w = RW,  h = 32,  oneWay = false },
        { x = 80,  y = 120,     w = 100, h = 12,  oneWay = true  },
        { x = 420, y = 115,     w = 110, h = 12,  oneWay = true  },
    },
    walls = {
        { x = 0,    y = -16, w = RW,  h = 16  },  -- ceiling
        { x = -16,  y = -16, w = 16,  h = RH + 32 },  -- left
        { x = RW,   y = -16, w = 16,  h = RH + 32 },  -- right
    },
    playerSpawn = { x = 60, y = FLOOR_Y - 32 },
    exitDoor    = { x = 8,  y = FLOOR_Y - 48, w = 24, h = 48 },
}

-- Per-visit state
local player      = nil
local roomManager = nil
local world       = nil
local camera      = nil
local platforms   = {}
local walls       = {}
local exitDoor    = nil
local pickups     = {}
local font        = nil

-- Activities
local slotMachine    = nil
local weaponAltar    = nil
local shrine         = nil
local pressurePlates = {}
local spikeTraps     = {}
local secretEntrance = nil

local doorSheet  = nil
local doorQuads  = {}
local DOOR_FRAME = 48

local CAM_ZOOM = 3
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
    local p = Pickup.new(x, y, rtype, value)
    world:add(p, p.x, p.y, p.w, p.h)
    table.insert(pickups, p)
end

---------------------------------------------------------------------------
function backroom:enter(_, _player, _roomManager)
    player      = _player
    roomManager = _roomManager

    player.combatDisabled = true
    player.vx = 0
    player.vy = 0

    font     = Font.new(12)
    world    = bump.newWorld(32)
    platforms = {}
    walls     = {}
    pickups   = {}
    pressurePlates = {}
    spikeTraps     = {}

    loadDoor()

    -- Platforms + walls
    for _, p in ipairs(ROOM.platforms) do
        local plat = { x=p.x, y=p.y, w=p.w, h=p.h, oneWay=p.oneWay or false, isPlatform=true }
        world:add(plat, plat.x, plat.y, plat.w, plat.h)
        table.insert(platforms, plat)
    end
    for _, w in ipairs(ROOM.walls) do
        local wall = { x=w.x, y=w.y, w=w.w, h=w.h, isWall=true }
        world:add(wall, wall.x, wall.y, wall.w, wall.h)
        table.insert(walls, wall)
    end

    -- Exit door
    local d = ROOM.exitDoor
    exitDoor = { x=d.x, y=d.y, w=d.w, h=d.h, isDoor=true }
    world:add(exitDoor, exitDoor.x, exitDoor.y, exitDoor.w, exitDoor.h)

    -- Player spawn
    local sp = ROOM.playerSpawn
    player.x, player.y = sp.x, sp.y
    player.grounded = false
    player.jumpCount = 0
    player.coyoteTimer = 0
    player.jumpBufferTimer = 0
    player.dashTimer = 0
    player.dashCooldown = 0
    world:add(player, player.x, player.y, player.w, player.h)

    -- Camera
    camera = Camera(sp.x, sp.y)
    camera.scale = CAM_ZOOM
    cam.currentX, cam.targetX = sp.x, sp.x
    cam.currentY, cam.targetY = sp.y, sp.y

    -- ── ACTIVITIES ──────────────────────────────────────────────────────

    -- Slot machine (x=160)
    local smX = 160
    slotMachine = SlotMachine.new(smX, FLOOR_Y - 45)
    slotMachine.onResult = function(rtype, value)
        local sx = slotMachine.x + slotMachine.w * 0.5
        spawnPickup(sx, slotMachine.y - 10, rtype, value)
    end

    -- Weapon altar (x=260, three pedestals ~36px apart)
    weaponAltar = WeaponAltar.new(260, FLOOR_Y - 48, 1)
    weaponAltar.onChoose = function(gun)
        if gun then
            spawnPickup(player.x, player.y - 20, "weapon", gun)
        end
    end

    -- Shrine (x=460)
    shrine = Shrine.new(460, FLOOR_Y - 40)
    shrine.onActivate = function(buffId)
        if player and buffId then
            local Buffs = require("src.systems.buffs")
            Buffs.apply(player, buffId, { source = "shrine" })
        end
    end

    -- Spike trap + pressure plate (x=560)
    local trap1 = SpikeTrap.new(555, FLOOR_Y - 8, 24)
    local trap2 = SpikeTrap.new(579, FLOOR_Y - 8, 24)
    table.insert(spikeTraps, trap1)
    table.insert(spikeTraps, trap2)

    local plate = PressurePlate.new(560, FLOOR_Y - 8, { trap1, trap2 })
    plate.onTrigger = function()
        -- damage player
        if player then
            local ok, dmg = player:takeDamage(10)
            if ok then
                DamageNumbers.spawn(player.x + player.w*0.5, player.y, dmg, "in")
            end
        end
    end
    table.insert(pressurePlates, plate)

    -- Secret entrance (decorative, left upper platform area x=85)
    secretEntrance = SecretEntrance.new(85, 94)
end

---------------------------------------------------------------------------
function backroom:leave()
    if world and player then
        if world:hasItem(player) then world:remove(player) end
    end
    player.combatDisabled = false
    world    = nil
    camera   = nil
    pickups  = {}
    pressurePlates = {}
    spikeTraps     = {}
    slotMachine    = nil
    weaponAltar    = nil
    shrine         = nil
    secretEntrance = nil
end

---------------------------------------------------------------------------
local function isNearDoor(p)
    local pcx = p.x + p.w * 0.5
    local pcy = p.y + p.h * 0.5
    local dcx = exitDoor.x + exitDoor.w * 0.5
    local dcy = exitDoor.y + exitDoor.h * 0.5
    local dx, dy = pcx - dcx, pcy - dcy
    return dx*dx + dy*dy < 50*50
end

function backroom:keypressed(key)
    if not player then return end
    local Keybinds = require("src.systems.keybinds")

    if Keybinds.matches("interact", key) or key == "e" then
        -- Exit door → back to saloon
        if isNearDoor(player) then
            local saloon = require("src.states.saloon")
            Gamestate.switch(saloon, player, roomManager)
            return
        end
        -- Slot machine
        if slotMachine and slotMachine:isNearPlayer(player.x + player.w*0.5, player.y + player.h*0.5) then
            slotMachine:tryPlay(player)
            return
        end
        -- Weapon altar
        if weaponAltar then
            weaponAltar:tryChoose(player)
            return
        end
        -- Shrine
        if shrine and shrine:isNearPlayer(player.x + player.w*0.5, player.y + player.h*0.5) then
            shrine:tryActivate(player)
            return
        end
    end

    if Keybinds.matches("jump", key) or key == "w" or key == "up" then
        player:jump()
    end
    if Keybinds.matches("drop", key) or key == "down" then
        player:tryDropThrough()
    end
end

---------------------------------------------------------------------------
function backroom:update(dt)
    if not player or not world then return end

    -- Player movement — delegate to player:update() exactly as the saloon does
    player:update(dt, world, {})

    -- Activities
    slotMachine:update(dt)
    if weaponAltar then weaponAltar:update(dt, player) end
    if shrine then shrine:update(dt) end
    for _, pp in ipairs(pressurePlates) do pp:update(dt, player) end
    for _, st in ipairs(spikeTraps)     do st:update(dt) end
    if secretEntrance then secretEntrance:update(dt, player) end

    -- Pickups
    for i = #pickups, 1, -1 do
        local p = pickups[i]
        p:update(dt, player, world)
        if p.collected then
            if world:hasItem(p) then world:remove(p) end
            table.remove(pickups, i)
        end
    end

    -- Clamp player to room bounds
    if player.x < 0 then player.x = 0 end
    if player.x + player.w > RW then player.x = RW - player.w end

    -- Camera lerp (same pattern as saloon)
    local sw, sh = love.graphics.getDimensions()
    local viewW, viewH = sw / CAM_ZOOM, sh / CAM_ZOOM
    local px = player.x + player.w * 0.5
    local py = player.y + player.h * 0.5
    cam.targetX = math.max(viewW*0.5, math.min(RW - viewW*0.5, px))
    cam.targetY = math.max(viewH*0.5, math.min(RH - viewH*0.5, py))
    local t = 1 - math.exp(-cam.lerpSpeed * dt)
    cam.currentX = cam.currentX + (cam.targetX - cam.currentX) * t
    cam.currentY = cam.currentY + (cam.targetY - cam.currentY) * t
    camera:lookAt(cam.currentX, cam.currentY)

    DamageNumbers.update(dt)
end

---------------------------------------------------------------------------
function backroom:draw()
    if not camera then return end
    local sw, sh = love.graphics.getDimensions()

    -- Background
    love.graphics.setColor(0.12, 0.08, 0.05)
    love.graphics.rectangle("fill", 0, 0, sw, sh)

    camera:attach()

    -- Floor / platforms
    love.graphics.setColor(0.28, 0.18, 0.10)
    for _, p in ipairs(platforms) do
        love.graphics.rectangle("fill", p.x, p.y, p.w, p.h)
        love.graphics.setColor(0.42, 0.28, 0.14)
        love.graphics.rectangle("fill", p.x, p.y, p.w, 3)
        love.graphics.setColor(0.28, 0.18, 0.10)
    end

    -- Activities
    if secretEntrance then secretEntrance:draw() end
    for _, st in ipairs(spikeTraps)     do st:draw() end
    for _, pp in ipairs(pressurePlates) do pp:draw() end
    if shrine      then shrine:draw(shrine:isNearPlayer(player.x + player.w*0.5, player.y + player.h*0.5)) end
    if weaponAltar then
        weaponAltar:updateSelection(player.x + player.w*0.5, player.y + player.h*0.5)
        weaponAltar:draw(weaponAltar:isNearPlayer(player.x + player.w*0.5, player.y + player.h*0.5))
    end
    slotMachine:draw(slotMachine:isNearPlayer(player.x + player.w*0.5, player.y + player.h*0.5))

    -- Pickups
    for _, p in ipairs(pickups) do p:draw() end

    -- Player
    player:draw()

    -- Exit door
    if exitDoor then
        if doorSheet and #doorQuads > 0 then
            love.graphics.setColor(1, 1, 1)
            local scale = exitDoor.h / DOOR_FRAME
            local drawX = exitDoor.x + exitDoor.w*0.5 - (DOOR_FRAME * scale)*0.5
            local drawY = exitDoor.y + exitDoor.h - DOOR_FRAME * scale
            love.graphics.draw(doorSheet, doorQuads[8], drawX, drawY, 0, scale, scale)
        else
            love.graphics.setColor(0.4, 0.25, 0.1)
            love.graphics.rectangle("fill", exitDoor.x, exitDoor.y, exitDoor.w, exitDoor.h)
        end
        if isNearDoor(player) then
            if font then love.graphics.setFont(font) end
            local label = "[E] Back to Saloon"
            local tw = (font or love.graphics.getFont()):getWidth(label)
            local dcx = exitDoor.x + exitDoor.w*0.5
            love.graphics.setColor(0, 0, 0, 0.7)
            love.graphics.print(label, math.floor(dcx - tw*0.5)+1, exitDoor.y - 15)
            love.graphics.setColor(1, 0.9, 0.5)
            love.graphics.print(label, math.floor(dcx - tw*0.5), exitDoor.y - 16)
        end
    end

    -- Labels above each activity
    if font then love.graphics.setFont(font) end
    local function label(x, y, text)
        local tw = (font or love.graphics.getFont()):getWidth(text)
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.print(text, math.floor(x - tw*0.5)+1, y+1)
        love.graphics.setColor(1, 0.85, 0.4)
        love.graphics.print(text, math.floor(x - tw*0.5), y)
    end
    label(slotMachine.x + slotMachine.w*0.5, slotMachine.y - 22, "Slot Machine")
    if weaponAltar then label(weaponAltar.x + 56, weaponAltar.y - 14, "Weapon Altar") end
    if shrine      then label(shrine.x + 12,      shrine.y - 14,      "Shrine")       end
    label(565, FLOOR_Y - 40, "Trap")
    if secretEntrance then label(secretEntrance.x + 12, secretEntrance.y - 14, "Secret Wall") end

    camera:detach()

    -- Screen-space: room title + damage numbers
    if font then love.graphics.setFont(font) end
    love.graphics.setColor(0.6, 0.5, 0.3, 0.7)
    love.graphics.printf("~ Back Room (Dev) ~", 0, 8, sw, "center")

    DamageNumbers.draw()
end

return backroom
