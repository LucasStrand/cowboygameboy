-- Shared first-room rendering for the main menu (matches game parallax + geometry).
local TileRenderer = require("src.systems.tile_renderer")
local RoomProps = require("src.systems.room_props")
local CAM_ZOOM = 2

local M = {}

-- Door sprite (shared with game state)
local doorSheet
local doorQuads = {}
local DOOR_FRAME_SIZE = 48

local function ensureDoorLoaded()
    if doorSheet then return end
    doorSheet = love.graphics.newImage("assets/SaloonDoor.png")
    doorSheet:setFilter("nearest", "nearest")
    local sw, sh = doorSheet:getDimensions()
    for i = 0, 7 do
        doorQuads[i + 1] = love.graphics.newQuad(
            i * DOOR_FRAME_SIZE, 0, DOOR_FRAME_SIZE, DOOR_FRAME_SIZE, sw, sh
        )
    end
end

--- @param camera hump.camera
--- @param currentRoom table from RoomManager:loadRoom
--- @param bgImage love.Image|nil
--- @param doorOpen boolean
--- @param showLockedLabel boolean show "Locked" when door closed (combat lock)
function M.draw(camera, currentRoom, bgImage, doorOpen, showLockedLabel)
    if not currentRoom then return end

    local camX, camY = camera:position()
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

    for _, wall in ipairs(currentRoom.walls) do
        TileRenderer.drawWall(wall.x, wall.y, wall.w, wall.h)
    end

    for _, plat in ipairs(currentRoom.platforms) do
        if plat.h >= 32 then
            TileRenderer.drawWall(plat.x, plat.y, plat.w, plat.h)
        else
            TileRenderer.drawPlatform(plat.x, plat.y, plat.w, plat.h)
        end
    end

    RoomProps.drawDecor(currentRoom)

    local door = currentRoom.door
    if door then
        ensureDoorLoaded()
        local frame = doorOpen and 8 or 1
        local quad = doorQuads[frame]
        if quad and doorSheet then
            love.graphics.setColor(1, 1, 1)
            local drawX = door.x + door.w / 2 - DOOR_FRAME_SIZE / 2
            local drawY = door.y + door.h - DOOR_FRAME_SIZE
            love.graphics.draw(doorSheet, quad, drawX, drawY)
        end

        if not doorOpen and showLockedLabel then
            love.graphics.setColor(1, 0.85, 0.35, 0.75)
            love.graphics.printf("Locked", door.x - 16, door.y - 18, door.w + 32, "center")
        end
    end

    love.graphics.setColor(1, 1, 1)
end

return M
