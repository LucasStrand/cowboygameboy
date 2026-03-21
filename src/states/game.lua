local Gamestate = require("lib.hump.gamestate")
local Camera = require("lib.hump.camera")
local bump = require("lib.bump")

local Player = require("src.entities.player")
local Enemy  = require("src.entities.enemy")
local Pickup = require("src.entities.pickup")

local Combat = require("src.systems.combat")
local RoomManager = require("src.systems.room_manager")
local HUD    = require("src.ui.hud")
local DevLog = require("src.ui.devlog")
local DamageNumbers = require("src.ui.damage_numbers")
local Font = require("src.ui.font")

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
-- After touching the exit while it's locked, keep off-screen enemy arrows until the room is clear
local offScreenEnemyHintActive = false

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

function game:init()
    bgImage = love.graphics.newImage("assets/backgrounds/forest.png")
    bgImage:setWrap("repeat", "clampzero")
end

function game:enter()
    world = bump.newWorld(32)
    camera = Camera(400, 200)
    camera.scale = CAM_ZOOM
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
    DevLog.init()
    DevLog.push("sys", "Run started")
    loadNextRoom()
end

function loadNextRoom()
    DamageNumbers.clear()
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

    processPendingEnemySpawns(dt)

    -- Aim point in world (same coords as shooting) for omnidirectional melee
    do
        local mx, my = love.mouse.getPosition()
        local gx, gy = windowToGame(mx, my)
        local wx, wy = camera:worldCoords(gx, gy, 0, 0, GAME_WIDTH, GAME_HEIGHT)
        player.aimWorldX = wx
        player.aimWorldY = wy
    end

    -- Player update
    player:update(dt, world, enemies)

    -- Auto-fire at optimal target (only when enemies are on screen; no gun while shielding)
    local camX, camY = camera:position()
    local halfW = GAME_WIDTH / (2 * CAM_ZOOM)
    local halfH = GAME_HEIGHT / (2 * CAM_ZOOM)
    local viewL, viewT = camX - halfW, camY - halfH
    local viewR, viewB = camX + halfW, camY + halfH
    if player.autoGun and not player.blocking and not player.reloading and player.shootCooldown <= 0 and player.ammo > 0 then
        local tx, ty = Combat.findAutoTarget(enemies, player, world, viewL, viewT, viewR, viewB)
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
    Combat.tryAutoMelee(player, enemies, world, viewL, viewT, viewR, viewB)
    Combat.checkPlayerMelee(player, enemies)

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

    DamageNumbers.update(dt)

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
    local leveledUp = Combat.checkPickups(pickups, player)

    -- Level up
    if leveledUp then
        DevLog.push("progress", "Level up → " .. player.level)
        local levelup = require("src.states.levelup")
        Gamestate.push(levelup, player, function() end)
    end

    -- Check if all enemies dead (and no staggered spawns left) -> open door
    if #enemies == 0 and not doorOpen and currentRoom and not pendingEnemiesIncoming() then
        doorOpen = true
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

    -- Exit door: use [E] when nearby (see tryExitThroughDoor)

    -- Kill plane (fell out of bounds)
    if isOutOfBounds(player, currentRoom) then
        player.hp = 0
    end

    -- Player death
    if player.hp <= 0 then
        DevLog.push("sys", string.format("Player died  lv%d  %d rooms  $%d",
            player.level, roomManager.totalRoomsCleared, player.gold))
        local gameover = require("src.states.gameover")
        Gamestate.switch(gameover, {
            level = player.level,
            roomsCleared = roomManager.totalRoomsCleared,
            gold = player.gold,
            perksCount = #player.perks,
        })
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
    if key == "space" or key == "w" or key == "up" then
        player:jump()
    end
    if key == "lshift" or key == "rshift" then
        player:tryDash()
    end
    if key == "s" or key == "down" then
        player:tryDropThrough()
    end
    if key == "r" then
        player:reload()
    end
    if key == "f" then
        player:meleeAttack()
    end
    if key == "e" then
        tryExitThroughDoor()
    end
    if key == "escape" then
        local menu = require("src.states.menu")
        Gamestate.switch(menu)
    end
end

function game:mousepressed(x, y, button)
    local gx, gy = windowToGame(x, y)
    if button == 1 and not player.blocking then
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

function game:draw()
    -- Camera with shake
    local sx, sy = 0, 0
    if shakeTimer > 0 then
        sx = (math.random() - 0.5) * shakeIntensity * 2
        sy = (math.random() - 0.5) * shakeIntensity * 2
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
            love.graphics.setColor(0.25, 0.16, 0.1)
            love.graphics.rectangle("fill", wall.x, wall.y, wall.w, wall.h)
            love.graphics.setColor(0.35, 0.22, 0.14)
            love.graphics.rectangle("fill", wall.x, wall.y, wall.w, 4)
        end

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

            if not doorOpen and roomHasLivingThreat() then
                love.graphics.setColor(1, 0.85, 0.35, 0.75)
                love.graphics.printf("Locked", door.x - 16, door.y - 18, door.w + 32, "center")
            end

            if doorOpen then
                love.graphics.setColor(1, 1, 1, 0.85)
                if player and isPlayerNearDoor() then
                    love.graphics.printf("[E] Exit", door.x - 24, door.y - 20, door.w + 48, "center")
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

    -- Bullets
    for _, b in ipairs(bullets) do
        b:draw()
    end

    DamageNumbers.draw()

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

    love.graphics.setColor(1, 1, 1)
end

return game
