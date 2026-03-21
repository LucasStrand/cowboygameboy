local Font = require("src.ui.font")

local HUD = {}

local LOADOUT_SLOT_W, LOADOUT_SLOT_H, LOADOUT_GAP = 58, 50, 6
local LOADOUT_BASE_X = 18

local function loadoutBaseY(screenH)
    return screenH - 96
end

--- Screen-space hit test (same coords as HUD.draw after origin): gx, gy in 0..GAME_WIDTH/HEIGHT
function HUD.hitLoadout(mx, my, screenH)
    local baseY = loadoutBaseY(screenH)
    local order = { "gun", "melee", "shield" }
    for i = 1, #order do
        local x = LOADOUT_BASE_X + (i - 1) * (LOADOUT_SLOT_W + LOADOUT_GAP)
        if mx >= x and mx <= x + LOADOUT_SLOT_W and my >= baseY and my <= baseY + LOADOUT_SLOT_H then
            return order[i]
        end
    end
    return nil
end

function HUD.draw(player)
    love.graphics.push()
    love.graphics.origin()

    local screenW = GAME_WIDTH
    local screenH = GAME_HEIGHT
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

    -- Block indicator (below ammo)
    if player.blocking then
        love.graphics.setColor(0.4, 0.6, 1.0, 0.9)
        love.graphics.print("[ BLOCKING ]", hpBarX, ammoY + 46)
    end

    -- Loadout row: revolver / melee / shield — right-click a slot toggles auto for that category
    do
        local baseY = loadoutBaseY(screenH)
        local shieldAutoCapable = player:shieldAllowsAutoBlock()
        local slots = {
            { id = "gun",    label = "Gun",    sub = "Revolver", auto = player.autoGun },
            { id = "melee",  label = "Melee",  sub = (player.gear.melee and player.gear.melee.name) or "—", auto = player.autoMelee },
            {
                id = "shield",
                label = "Shield",
                sub = (player.gear.shield and player.gear.shield.name) or "—",
                auto = shieldAutoCapable and player.autoBlock,
                shieldMode = shieldAutoCapable,
            },
        }
        if not HUD._loadoutTinyFont then
            HUD._loadoutTinyFont = Font.new(10)
        end
        local prevFont = love.graphics.getFont()
        love.graphics.setFont(HUD._loadoutTinyFont)

        for i, slot in ipairs(slots) do
            local x = LOADOUT_BASE_X + (i - 1) * (LOADOUT_SLOT_W + LOADOUT_GAP)
            love.graphics.setColor(0.1, 0.1, 0.12, 0.92)
            love.graphics.rectangle("fill", x, baseY, LOADOUT_SLOT_W, LOADOUT_SLOT_H)

            local borderOn = slot.auto
            if borderOn then
                love.graphics.setColor(0.25, 0.9, 0.45, 0.95)
            else
                love.graphics.setColor(0.38, 0.38, 0.42, 0.85)
            end
            love.graphics.setLineWidth(borderOn and 3 or 2)
            love.graphics.rectangle("line", x, baseY, LOADOUT_SLOT_W, LOADOUT_SLOT_H)
            love.graphics.setLineWidth(1)

            if slot.id == "melee" and player.meleeHitFlashTimer > 0 then
                local p = player.meleeHitFlashTimer / 0.2
                love.graphics.setColor(1, 0.45, 0.2, 0.55 + 0.45 * p)
                love.graphics.setLineWidth(4)
                love.graphics.rectangle("line", x - 2, baseY - 2, LOADOUT_SLOT_W + 4, LOADOUT_SLOT_H + 4)
                love.graphics.setLineWidth(1)
            end

            love.graphics.setColor(1, 1, 1, borderOn and 1 or 0.65)
            love.graphics.printf(slot.label, x + 2, baseY + 4, LOADOUT_SLOT_W - 4, "center")
            love.graphics.setColor(0.85, 0.85, 0.9, borderOn and 0.9 or 0.55)
            love.graphics.printf(slot.sub, x + 2, baseY + 18, LOADOUT_SLOT_W - 4, "center")
            love.graphics.setColor(0.55, 0.95, 0.65, borderOn and 1 or 0.35)
            if slot.id == "shield" and not slot.shieldMode then
                love.graphics.setColor(0.55, 0.55, 0.6, 0.75)
                love.graphics.printf("CTRL", x + 2, baseY + 34, LOADOUT_SLOT_W - 4, "center")
            else
                love.graphics.printf(borderOn and "AUTO" or "off", x + 2, baseY + 34, LOADOUT_SLOT_W - 4, "center")
            end
        end

        love.graphics.setFont(prevFont)
        love.graphics.setColor(0.65, 0.65, 0.7, 0.75)
        love.graphics.print("RMB slot: toggle auto", LOADOUT_BASE_X, baseY - 14)
    end

    -- Room info (top center)
    love.graphics.setColor(1, 1, 1, 0.7)

    love.graphics.pop()
    love.graphics.setColor(1, 1, 1)
end

function HUD.drawRoomInfo(roomIndex, totalRooms)
    love.graphics.push()
    love.graphics.origin()
    love.graphics.setColor(1, 1, 1, 0.7)
    love.graphics.printf("Room " .. roomIndex .. "/" .. totalRooms, 0, 20, GAME_WIDTH, "center")
    love.graphics.pop()
    love.graphics.setColor(1, 1, 1)
end

return HUD
