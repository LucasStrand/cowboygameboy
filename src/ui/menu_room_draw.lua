-- Shared first-room rendering for the main menu (matches game parallax + geometry).
local CAM_ZOOM = 2

local M = {}

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
        love.graphics.setColor(0.25, 0.16, 0.1)
        love.graphics.rectangle("fill", wall.x, wall.y, wall.w, wall.h)
        love.graphics.setColor(0.35, 0.22, 0.14)
        love.graphics.rectangle("fill", wall.x, wall.y, wall.w, 4)
    end

    for _, plat in ipairs(currentRoom.platforms) do
        love.graphics.setColor(0.55, 0.35, 0.2)
        love.graphics.rectangle("fill", plat.x, plat.y, plat.w, 4)
        love.graphics.setColor(0.35, 0.22, 0.12)
        love.graphics.rectangle("fill", plat.x, plat.y + 4, plat.w, plat.h - 4)
    end

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

        if not doorOpen and showLockedLabel then
            love.graphics.setColor(1, 0.85, 0.35, 0.75)
            love.graphics.printf("Locked", door.x - 16, door.y - 18, door.w + 32, "center")
        end
    end

    love.graphics.setColor(1, 1, 1)
end

return M
