local Gamestate = require("lib.hump.gamestate")
local Camera = require("lib.hump.camera")
local bump = require("lib.bump")

local Player = require("src.entities.player")
local Pickup = require("src.entities.pickup")

local Combat = require("src.systems.combat")
local RoomManager = require("src.systems.room_manager")
local HUD = require("src.ui.hud")

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
local transitionTimer
local paused

function game:init()
end

function game:enter()
    world = bump.newWorld(32)
    camera = Camera(400, 200)
    player = Player.new(50, 300)
    world:add(player, player.x, player.y, player.w, player.h)
    player.isPlayer = true

    bullets = {}
    enemies = {}
    pickups = {}
    shakeTimer = 0
    shakeIntensity = 0
    gameTimer = 0
    doorOpen = false
    transitionTimer = 0
    paused = false

    roomManager = RoomManager.new()
    roomManager:generateSequence()
    loadNextRoom()
end

function loadNextRoom()
    -- Clean up old world items
    local items, len = world:getItems()
    for i = 1, len do
        world:remove(items[i])
    end
    bullets = {}
    pickups = {}
    enemies = {}
    doorOpen = false

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
end

function game:resume()
    -- Returning from saloon -> load new cycle of rooms
    if roomManager.needsNewRooms then
        roomManager.needsNewRooms = false
        loadNextRoom()
    end
end

function game:update(dt)
    if paused then return end

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

    -- Player update
    player:update(dt, world)

    Combat.updateBullets(bullets, dt, world, enemies, player)

    -- Enemies update
    local i = 1
    while i <= #enemies do
        local e = enemies[i]
        if e.alive then
            local bulletData = e:update(dt, world, player.x + player.w/2, player.y + player.h/2)
            if bulletData then
                local b = Combat.spawnBullet(world, bulletData)
                table.insert(bullets, b)
            end
            i = i + 1
        else
            local enemyDrops = Combat.onEnemyKilled(e, player)
            if enemyDrops then
                for _, drop in ipairs(enemyDrops) do
                    local p = Pickup.new(drop.x, drop.y, drop.type, drop.value)
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

    -- Pickups update
    for _, p in ipairs(pickups) do
        p:update(dt)
    end

    -- Remove dead pickups
    i = 1
    while i <= #pickups do
        if not pickups[i].alive then
            table.remove(pickups, i)
        else
            i = i + 1
        end
    end

    -- Check pickup collection
    local leveledUp = Combat.checkPickups(pickups, player)

    -- Level up
    if leveledUp then
        local levelup = require("src.states.levelup")
        Gamestate.push(levelup, player, function() end)
    end

    -- Check if all enemies dead -> open door
    if #enemies == 0 and not doorOpen and currentRoom then
        doorOpen = true
        if currentRoom.door then
            currentRoom.door.locked = false
        end
    end

    -- Check door collision
    if doorOpen and currentRoom and currentRoom.door then
        local door = currentRoom.door
        local px = player.x + player.w / 2
        local py = player.y + player.h / 2
        local dx = (door.x + door.w / 2) - px
        local dy = (door.y + door.h / 2) - py
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist < 40 then
            roomManager:onRoomCleared()
            if roomManager:isCheckpoint() then
                local saloon = require("src.states.saloon")
                Gamestate.push(saloon, player, roomManager)
            else
                transitionTimer = 0.5
            end
        end
    end

    -- Kill plane (fell into pit)
    if currentRoom and player.y > currentRoom.height + 100 then
        player.hp = 0
    end

    -- Player death
    if player.hp <= 0 then
        local gameover = require("src.states.gameover")
        Gamestate.switch(gameover, {
            level = player.level,
            roomsCleared = roomManager.totalRoomsCleared,
            gold = player.gold,
            perksCount = #player.perks,
        })
        return
    end

    -- Camera follow (center on room if room smaller than viewport)
    if currentRoom then
        local cx, cy
        if currentRoom.width <= GAME_WIDTH then
            cx = currentRoom.width / 2
        else
            cx = math.max(GAME_WIDTH / 2, math.min(currentRoom.width - GAME_WIDTH / 2, player.x + player.w / 2))
        end
        if currentRoom.height <= GAME_HEIGHT then
            cy = currentRoom.height / 2
        else
            cy = math.max(GAME_HEIGHT / 2, math.min(currentRoom.height - GAME_HEIGHT / 2, player.y + player.h / 2))
        end
        camera:lookAt(cx, cy)
    end
end

function game:keypressed(key)
    if key == "space" or key == "w" or key == "up" then
        player:jump()
    end
    if key == "r" then
        player:reload()
    end
    if key == "escape" then
        local menu = require("src.states.menu")
        Gamestate.switch(menu)
    end
end

function game:mousepressed(x, y, button)
    if button == 1 then
        local mx, my = camera:worldCoords(x, y)
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
        player:reload()
    end
end

function game:draw()
    -- Camera with shake
    local sx, sy = 0, 0
    if shakeTimer > 0 then
        sx = (math.random() - 0.5) * shakeIntensity * 2
        sy = (math.random() - 0.5) * shakeIntensity * 2
    end

    camera:attach()
    love.graphics.translate(sx, sy)

    -- Room background
    if currentRoom then
        -- Sky
        love.graphics.setColor(0.15, 0.1, 0.08)
        love.graphics.rectangle("fill", -50, -50, currentRoom.width + 100, currentRoom.height + 100)

        -- Platforms
        for _, plat in ipairs(currentRoom.platforms) do
            -- Top surface
            love.graphics.setColor(0.55, 0.35, 0.2)
            love.graphics.rectangle("fill", plat.x, plat.y, plat.w, 4)
            -- Body
            love.graphics.setColor(0.35, 0.22, 0.12)
            love.graphics.rectangle("fill", plat.x, plat.y + 4, plat.w, plat.h - 4)
        end

        -- Door
        local door = currentRoom.door
        if door then
            if doorOpen then
                love.graphics.setColor(0.2, 0.8, 0.2)
            else
                love.graphics.setColor(0.5, 0.1, 0.1)
            end
            love.graphics.rectangle("fill", door.x, door.y, door.w, door.h)
            love.graphics.setColor(0.8, 0.7, 0.4)
            love.graphics.rectangle("line", door.x, door.y, door.w, door.h)

            if doorOpen then
                love.graphics.setColor(1, 1, 1, 0.8)
                love.graphics.printf("EXIT", door.x - 10, door.y - 18, door.w + 20, "center")
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

    -- Bullets
    for _, b in ipairs(bullets) do
        b:draw()
    end

    -- Debug
    if DEBUG then
        love.graphics.setColor(0, 1, 0, 0.3)
        local items, len = world:getItems()
        for i = 1, len do
            local x, y, w, h = world:getRect(items[i])
            love.graphics.rectangle("line", x, y, w, h)
        end
    end

    camera:detach()

    -- HUD (screen space)
    HUD.draw(player)
    if roomManager then
        HUD.drawRoomInfo(roomManager.currentRoomIndex, #roomManager.roomSequence)
    end

    -- Transition fade
    if transitionTimer > 0 then
        local alpha = 1 - (transitionTimer / 0.5)
        love.graphics.setColor(0, 0, 0, alpha)
        love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
    end

    -- Dead eye indicator
    if player.deadEyeTimer > 0 then
        love.graphics.setColor(1, 0.2, 0.2, 0.2)
        love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
        love.graphics.setColor(1, 0.5, 0.2)
        love.graphics.printf("DEAD EYE", 0, love.graphics.getHeight() / 2 - 100, love.graphics.getWidth(), "center")
    end

    love.graphics.setColor(1, 1, 1)
end

return game
