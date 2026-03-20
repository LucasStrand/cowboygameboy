local HUD = {}

function HUD.draw(player)
    love.graphics.push()
    love.graphics.origin()

    local screenW = love.graphics.getWidth()
    local screenH = love.graphics.getHeight()
    local effectiveStats = player:getEffectiveStats()

    -- HP Bar (top left)
    local hpBarX = 20
    local hpBarY = 20
    local hpBarW = 200
    local hpBarH = 20
    local hpRatio = player.hp / effectiveStats.maxHP

    love.graphics.setColor(0.2, 0.2, 0.2, 0.8)
    love.graphics.rectangle("fill", hpBarX - 2, hpBarY - 2, hpBarW + 4, hpBarH + 4)
    love.graphics.setColor(0.3, 0.0, 0.0)
    love.graphics.rectangle("fill", hpBarX, hpBarY, hpBarW, hpBarH)
    love.graphics.setColor(0.8, 0.1, 0.1)
    love.graphics.rectangle("fill", hpBarX, hpBarY, hpBarW * hpRatio, hpBarH)
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf(player.hp .. "/" .. effectiveStats.maxHP, hpBarX, hpBarY + 2, hpBarW, "center")

    -- Ammo Cylinder (top left, below HP)
    local ammoY = hpBarY + hpBarH + 10
    local cylinderSize = effectiveStats.cylinderSize
    for i = 1, cylinderSize do
        local cx = hpBarX + (i - 1) * 18
        if i <= player.ammo then
            love.graphics.setColor(1, 0.85, 0.2)
            love.graphics.rectangle("fill", cx, ammoY, 12, 16)
            love.graphics.setColor(0.8, 0.65, 0.1)
            love.graphics.rectangle("fill", cx + 2, ammoY, 8, 4)
        else
            love.graphics.setColor(0.3, 0.3, 0.3, 0.5)
            love.graphics.rectangle("fill", cx, ammoY, 12, 16)
        end
    end

    if player.reloading then
        love.graphics.setColor(1, 0.5, 0.2)
        local reloadW = hpBarW * (1 - player.reloadTimer / effectiveStats.reloadSpeed)
        love.graphics.rectangle("fill", hpBarX, ammoY + 20, reloadW, 4)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print("RELOADING...", hpBarX, ammoY + 26)
    end

    -- XP Bar (bottom of screen)
    local xpBarW = 300
    local xpBarH = 10
    local xpBarX = (screenW - xpBarW) / 2
    local xpBarY = screenH - 30
    local xpRatio = player.xp / player.xpToNext

    love.graphics.setColor(0.2, 0.2, 0.2, 0.8)
    love.graphics.rectangle("fill", xpBarX - 1, xpBarY - 1, xpBarW + 2, xpBarH + 2)
    love.graphics.setColor(0.1, 0.2, 0.4)
    love.graphics.rectangle("fill", xpBarX, xpBarY, xpBarW, xpBarH)
    love.graphics.setColor(0.3, 0.6, 1.0)
    love.graphics.rectangle("fill", xpBarX, xpBarY, xpBarW * xpRatio, xpBarH)
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf("LV " .. player.level, xpBarX, xpBarY - 16, xpBarW, "center")

    -- Gold (top right)
    love.graphics.setColor(1, 0.85, 0.2)
    love.graphics.printf("$ " .. player.gold, screenW - 160, 20, 140, "right")

    -- Room info (top center)
    love.graphics.setColor(1, 1, 1, 0.7)

    love.graphics.pop()
    love.graphics.setColor(1, 1, 1)
end

function HUD.drawRoomInfo(roomIndex, totalRooms)
    love.graphics.push()
    love.graphics.origin()
    local screenW = love.graphics.getWidth()
    love.graphics.setColor(1, 1, 1, 0.7)
    love.graphics.printf("Room " .. roomIndex .. "/" .. totalRooms, 0, 20, screenW, "center")
    love.graphics.pop()
    love.graphics.setColor(1, 1, 1)
end

return HUD
