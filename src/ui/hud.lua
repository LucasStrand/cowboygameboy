local Font = require("src.ui.font")
local Guns = require("src.data.guns")



local HUD = {}



-- Loadout hit-test (must match draw positions)

local LOADOUT_SLOT_W, LOADOUT_SLOT_H, LOADOUT_GAP = 64, 52, 8

local LOADOUT_BASE_X = 12



local function loadoutBaseY(screenH)

    -- Room for larger revolver drum + hint above weapon slots

    return screenH - 112

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



local function ensureFonts()

    if HUD._fontHud then return end

    HUD._fontHud = Font.hudPrimary()

    HUD._fontHudSm = Font.hudSecondary()

    HUD._lineH = HUD._fontHud:getHeight()

    HUD._lineHSm = HUD._fontHudSm:getHeight()

    HUD._fontLoadout = Font.new(12)

    HUD._fontLoadoutSm = Font.new(10)

    HUD._fontRoom = Font.new(14)

    HUD._fontDeadEye = Font.new(36)

end



-- Dark outline for readability on busy backgrounds

local function shadowPrint(text, x, y, r, g, b, a)

    a = a or 1

    x = math.floor(x + 0.5)

    y = math.floor(y + 0.5)

    love.graphics.setColor(0.02, 0.02, 0.04, 0.92 * a)

    for ox = -1, 1 do

        for oy = -1, 1 do

            if ox ~= 0 or oy ~= 0 then

                love.graphics.print(text, x + ox, y + oy)

            end

        end

    end

    love.graphics.setColor(r, g, b, a)

    love.graphics.print(text, x, y)

end



local function shadowPrintf(text, x, y, limit, align, r, g, b, a)

    a = a or 1

    x = math.floor(x + 0.5)

    y = math.floor(y + 0.5)

    love.graphics.setColor(0.02, 0.02, 0.04, 0.92 * a)

    for ox = -1, 1 do

        for oy = -1, 1 do

            if ox ~= 0 or oy ~= 0 then

                love.graphics.printf(text, x + ox, y + oy, limit, align)

            end

        end

    end

    love.graphics.setColor(r, g, b, a)

    love.graphics.printf(text, x, y, limit, align)

end



local function drumOuterRadius(n)

    n = math.max(1, math.floor(n))

    -- Larger on-screen drum; still scales up slightly with chamber count

    return math.max(36, math.min(54, 30 + n * 0.75))

end



--- Top-down revolver drum: N chambers around a ring, first `loadedCount` filled.

local function drawRevolverCylinder(cx, cy, n, loadedCount, reloading)

    n = math.max(1, math.floor(n))

    loadedCount = math.max(0, math.min(n, math.floor(loadedCount)))



    local outerR = drumOuterRadius(n)

    local Rch = outerR * 0.58

    local gap = 2.2

    local holeR

    if n <= 1 then

        holeR = math.min(7.5, outerR * 0.38)

    else

        holeR = Rch * math.sin(math.pi / n) - gap

        holeR = math.max(2.5, math.min(7.8, holeR))

    end

    local centerHoleR = math.max(3.5, outerR * 0.14)



    -- Drum body

    love.graphics.setColor(0.11, 0.1, 0.09)

    love.graphics.circle("fill", cx, cy, outerR + 1)

    love.graphics.setColor(0.22, 0.2, 0.18)

    love.graphics.circle("fill", cx, cy, outerR)

    love.graphics.setColor(0.38, 0.34, 0.3)

    love.graphics.setLineWidth(2)

    love.graphics.circle("line", cx, cy, outerR)

    love.graphics.setLineWidth(1)

    love.graphics.setColor(0.5, 0.45, 0.38, 0.35)

    love.graphics.circle("line", cx, cy, outerR - 2)



    if reloading then

        love.graphics.setColor(0.75, 0.55, 0.2, 0.22)

        love.graphics.setLineWidth(2)

        love.graphics.circle("line", cx, cy, outerR + 1)

        love.graphics.setLineWidth(1)

    end



    -- Center (crane / axle hole)

    love.graphics.setColor(0.06, 0.05, 0.05)

    love.graphics.circle("fill", cx, cy, centerHoleR + 1)

    love.graphics.setColor(0.14, 0.12, 0.11)

    love.graphics.circle("fill", cx, cy, centerHoleR)

    love.graphics.setColor(0.28, 0.25, 0.22)

    love.graphics.circle("line", cx, cy, centerHoleR)



    for i = 1, n do

        local ang = (i - 1) * (2 * math.pi / n) - math.pi / 2

        local sx = cx + math.cos(ang) * Rch

        local sy = cy + math.sin(ang) * Rch

        local loaded = i <= loadedCount

        if loaded then

            love.graphics.setColor(0.1, 0.08, 0.06)

            love.graphics.circle("fill", sx, sy, holeR + 1.5)

            love.graphics.setColor(0.92, 0.68, 0.16)

            love.graphics.circle("fill", sx, sy, holeR)

            love.graphics.setColor(1, 0.88, 0.42)

            love.graphics.circle("fill", sx, sy - holeR * 0.35, holeR * 0.45)

            love.graphics.setColor(0.45, 0.32, 0.06)

            love.graphics.circle("fill", sx, sy + holeR * 0.35, holeR * 0.4)

        else

            love.graphics.setColor(0.07, 0.07, 0.08)

            love.graphics.circle("fill", sx, sy, holeR + 0.5)

            love.graphics.setColor(0.16, 0.15, 0.14)

            love.graphics.circle("fill", sx, sy, holeR)

            love.graphics.setColor(0.32, 0.3, 0.28, 0.85)

            love.graphics.circle("line", sx, sy, holeR)

        end

    end

end



--- Double-barrel view: two large circles (barrels from the front), gold = loaded.
local function drawDoubleBarrel(cx, cy, capacity, loadedCount, reloading)
    capacity = math.max(1, math.floor(capacity))
    loadedCount = math.max(0, math.min(capacity, math.floor(loadedCount)))

    local barrelR = 14
    local gap = 6
    local totalH = capacity * (barrelR * 2 + gap) - gap
    local startY = cy - totalH / 2 + barrelR

    -- Outer housing
    love.graphics.setColor(0.11, 0.1, 0.09)
    love.graphics.rectangle("fill", cx - barrelR - 6, cy - totalH / 2 - 6,
                            (barrelR + 6) * 2, totalH + 12, 4, 4)
    love.graphics.setColor(0.22, 0.2, 0.18)
    love.graphics.rectangle("fill", cx - barrelR - 4, cy - totalH / 2 - 4,
                            (barrelR + 4) * 2, totalH + 8, 3, 3)
    love.graphics.setColor(0.38, 0.34, 0.3)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", cx - barrelR - 4, cy - totalH / 2 - 4,
                            (barrelR + 4) * 2, totalH + 8, 3, 3)
    love.graphics.setLineWidth(1)

    if reloading then
        love.graphics.setColor(0.75, 0.55, 0.2, 0.22)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", cx - barrelR - 5, cy - totalH / 2 - 5,
                                (barrelR + 5) * 2, totalH + 10, 4, 4)
        love.graphics.setLineWidth(1)
    end

    for i = 1, capacity do
        local by = startY + (i - 1) * (barrelR * 2 + gap)
        local loaded = i <= loadedCount

        if loaded then
            love.graphics.setColor(0.1, 0.08, 0.06)
            love.graphics.circle("fill", cx, by, barrelR + 1.5)
            love.graphics.setColor(0.92, 0.68, 0.16)
            love.graphics.circle("fill", cx, by, barrelR)
            love.graphics.setColor(1, 0.88, 0.42)
            love.graphics.circle("fill", cx, by - barrelR * 0.3, barrelR * 0.4)
            love.graphics.setColor(0.45, 0.32, 0.06)
            love.graphics.circle("fill", cx, by + barrelR * 0.3, barrelR * 0.35)
        else
            love.graphics.setColor(0.07, 0.07, 0.08)
            love.graphics.circle("fill", cx, by, barrelR + 0.5)
            love.graphics.setColor(0.16, 0.15, 0.14)
            love.graphics.circle("fill", cx, by, barrelR)
            love.graphics.setColor(0.32, 0.3, 0.28, 0.85)
            love.graphics.circle("line", cx, by, barrelR)
        end
    end
end

--- Magazine counter: rectangular mag shape with ammo count number.
local function drawMagazineCounter(cx, cy, capacity, loadedCount, reloading)
    capacity = math.max(1, math.floor(capacity))
    loadedCount = math.max(0, math.min(capacity, math.floor(loadedCount)))

    local magW, magH = 28, 56
    local mx = cx - magW / 2
    local my = cy - magH / 2

    -- Magazine body (olive/military green)
    love.graphics.setColor(0.11, 0.1, 0.09)
    love.graphics.rectangle("fill", mx - 1, my - 1, magW + 2, magH + 2, 3, 3)
    love.graphics.setColor(0.28, 0.32, 0.22)
    love.graphics.rectangle("fill", mx, my, magW, magH, 2, 2)

    -- Fill bar (bottom-up, representing remaining ammo)
    local fillRatio = loadedCount / capacity
    local fillH = math.floor((magH - 4) * fillRatio)
    if fillH > 0 then
        love.graphics.setColor(0.45, 0.52, 0.3)
        love.graphics.rectangle("fill", mx + 2, my + magH - 2 - fillH, magW - 4, fillH)
        love.graphics.setColor(0.58, 0.65, 0.4, 0.5)
        love.graphics.rectangle("fill", mx + 2, my + magH - 2 - fillH, magW - 4, math.min(2, fillH))
    end

    -- Border
    love.graphics.setColor(0.45, 0.42, 0.35)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", mx, my, magW, magH, 2, 2)
    love.graphics.setLineWidth(1)

    if reloading then
        love.graphics.setColor(0.75, 0.55, 0.2, 0.22)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", mx - 1, my - 1, magW + 2, magH + 2, 3, 3)
        love.graphics.setLineWidth(1)
    end

    -- Ammo count number (centered)
    if not HUD._fontMag then
        HUD._fontMag = Font.new(18)
    end
    local prev = love.graphics.getFont()
    love.graphics.setFont(HUD._fontMag)
    local numStr = tostring(loadedCount)
    local tw = HUD._fontMag:getWidth(numStr)
    local th = HUD._fontMag:getHeight()
    -- Shadow
    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.print(numStr, cx - tw / 2 + 1, cy - th / 2 + 1)
    -- Text
    if loadedCount <= math.ceil(capacity * 0.2) then
        love.graphics.setColor(1, 0.3, 0.2)  -- low ammo = red
    else
        love.graphics.setColor(1, 0.95, 0.85)
    end
    love.graphics.print(numStr, cx - tw / 2, cy - th / 2)
    love.graphics.setFont(prev)
end

--- Compute capacity for a specific gun using perk delta (independent of active weapon).
local BASE_CYLINDER_SIZE = 6  -- must match PLAYER_BASE_GUN_STATS.cylinderSize in player.lua
local function gunCapacity(gun, player)
    local perkDelta = player.stats.cylinderSize - BASE_CYLINDER_SIZE
    return gun.baseStats.cylinderSize + perkDelta
end

--- Dispatch to the correct ammo display based on active weapon type.
local function drawAmmoDisplay(cx, cy, player, effectiveStats)
    local gun = player:getActiveGun()
    if not gun then return 0 end  -- melee active, no ammo display

    local cap = gunCapacity(gun, player)
    local ammoType = gun.ammoType
    if ammoType == "cylinder" then
        drawRevolverCylinder(cx, cy, cap, player.ammo, player.reloading)
        return drumOuterRadius(cap)
    elseif ammoType == "double_barrel" then
        drawDoubleBarrel(cx, cy, cap, player.ammo, player.reloading)
        return 24  -- approximate visual radius
    elseif ammoType == "magazine" then
        drawMagazineCounter(cx, cy, cap, player.ammo, player.reloading)
        return 30  -- approximate visual radius
    end
    return 0
end

--- Draw ammo for a specific gun (used by akimbo to draw each slot independently).
local function drawAmmoForGun(cx, cy, gun, capacity, loadedCount, reloading)
    if not gun then return end
    local ammoType = gun.ammoType
    if ammoType == "cylinder" then
        drawRevolverCylinder(cx, cy, capacity, loadedCount, reloading)
    elseif ammoType == "double_barrel" then
        drawDoubleBarrel(cx, cy, capacity, loadedCount, reloading)
    elseif ammoType == "magazine" then
        drawMagazineCounter(cx, cy, capacity, loadedCount, reloading)
    end
end

function HUD.draw(player)

    ensureFonts()

    love.graphics.push()

    love.graphics.origin()



    local screenW = GAME_WIDTH

    local screenH = GAME_HEIGHT

    local effectiveStats = player:getEffectiveStats()



    local prevFont = love.graphics.getFont()



    -- —— HP + XP: floating text + thin bars

    do

        local panelW = 268

        local barH = 5

        local rowGap = 6

        -- Same logical size as menu subtitle (Font.hudPrimary); was _fontHudSm and looked much smaller.

        local lineH = HUD._lineH

        local innerW = panelW

        local hpRatio = math.max(0, math.min(1, player.hp / math.max(1, effectiveStats.maxHP)))

        local xpRatio = math.max(0, math.min(1, player.xp / player.xpToNext))

        local panelH = lineH + barH + rowGap + lineH + barH

        local bx = (screenW - innerW) / 2

        local panelY = screenH - panelH - 20

        local yLine1 = panelY

        local yBarHp = yLine1 + lineH - 1

        local yLine2 = yBarHp + barH + rowGap

        local yBarXp = yLine2 + lineH - 1



        love.graphics.setFont(HUD._fontHud)

        shadowPrintf(

            string.format("HP: %d / %d", player.hp, effectiveStats.maxHP),

            bx, yLine1, innerW, "center",

            0.88, 0.78, 0.7, 1

        )

        love.graphics.setColor(0.12, 0.04, 0.04, 0.55)

        love.graphics.rectangle("fill", bx, yBarHp, innerW, barH)

        love.graphics.setColor(0.9, 0.26, 0.2)

        love.graphics.rectangle("fill", bx, yBarHp, innerW * hpRatio, barH)

        love.graphics.setColor(1, 0.55, 0.45, 0.4)

        love.graphics.rectangle("fill", bx, yBarHp, innerW * hpRatio, math.min(2, barH))



        shadowPrintf(

            string.format("LV %d  ·  XP %d / %d", player.level, player.xp, player.xpToNext),

            bx, yLine2, innerW, "center",

            0.75, 0.85, 0.95, 0.95

        )

        love.graphics.setColor(0.08, 0.1, 0.18, 0.55)

        love.graphics.rectangle("fill", bx, yBarXp, innerW, barH)

        love.graphics.setColor(0.25, 0.48, 0.9)

        love.graphics.rectangle("fill", bx, yBarXp, innerW * xpRatio, barH)

        love.graphics.setColor(0.5, 0.75, 1)

        love.graphics.rectangle("fill", bx, yBarXp, innerW * xpRatio, barH)

        love.graphics.setColor(0.65, 0.88, 1, 0.35)

        love.graphics.rectangle("fill", bx, yBarXp, innerW * xpRatio, math.min(2, barH))

    end



    -- —— Gold (top right, floating) ——

    local goldW = 220

    local goldX = screenW - goldW - 14

    local goldY = 14

    love.graphics.setFont(HUD._fontHud)

    shadowPrintf(string.format("Gold: $%d", player.gold), goldX, goldY, goldW, "right", 1, 0.92, 0.82, 0.45, 1)



    -- —— Loadout row + ammo display (bottom-left) ——

    do

        local baseY = loadoutBaseY(screenH)

        local ammoColX = LOADOUT_BASE_X

        local hintY = baseY - 16

        local yCursor = hintY - 8



        if player.blocking then

            love.graphics.setFont(HUD._fontHud)

            local bh = HUD._fontHud:getHeight()

            local by = yCursor - bh

            shadowPrint("BLOCKING", ammoColX + 4, by, 0.55, 0.78, 1, 1)

            yCursor = by - 6

        end



        -- Use weapon-specific ammo display
        local isAkimbo = player.isAkimbo and player:isAkimbo()

        if isAkimbo then
            -- Akimbo: draw both weapons' ammo side by side
            local slot1 = player.weapons[1]
            local slot2 = player.weapons[2]
            local gun1 = slot1 and slot1.gun
            local gun2 = slot2 and slot2.gun

            local function ammoR(gun)
                if not gun then return 20 end
                if gun.ammoType == "cylinder" then
                    return drumOuterRadius(gunCapacity(gun, player))
                elseif gun.ammoType == "double_barrel" then return 24
                elseif gun.ammoType == "magazine" then return 30
                end
                return 20
            end

            local r1 = ammoR(gun1)
            local r2 = ammoR(gun2)
            local gap = 8

            -- Slot 1 (left)
            local cx1 = ammoColX + r1
            local cy1 = yCursor - math.max(r1, r2)
            if gun1 then
                local ammo1 = player.activeWeaponSlot == 1 and player.ammo or slot1.ammo
                local reloading1 = player.activeWeaponSlot == 1 and player.reloading or slot1.reloading
                drawAmmoForGun(cx1, cy1, gun1, gunCapacity(gun1, player), ammo1, reloading1)
            end

            -- Slot 2 (right of slot 1)
            local cx2 = cx1 + r1 + gap + r2
            if gun2 then
                local ammo2 = player.activeWeaponSlot == 2 and player.ammo or slot2.ammo
                local reloading2 = player.activeWeaponSlot == 2 and player.reloading or slot2.reloading
                drawAmmoForGun(cx2, cy1, gun2, gunCapacity(gun2, player), ammo2, reloading2)
            end
        else
            local displayR = 36
            local gun = player:getActiveGun()
            if gun and gun.ammoType == "cylinder" then
                displayR = drumOuterRadius(gunCapacity(gun, player))
            elseif gun and gun.ammoType == "double_barrel" then
                displayR = 24
            elseif gun and gun.ammoType == "magazine" then
                displayR = 30
            end

            local displayCy = yCursor - displayR
            local displayCx = ammoColX + displayR
            drawAmmoDisplay(displayCx, displayCy, player, effectiveStats)
        end

    end



    do

        local baseY = loadoutBaseY(screenH)

        local shieldAutoCapable = player:shieldAllowsAutoBlock()

        -- Slot 1: primary weapon, Slot 2: secondary weapon or melee, Slot 3: shield
        local gun1 = player.weapons[1] and player.weapons[1].gun
        local gun2 = player.weapons[2] and player.weapons[2].gun

        local function gunSlotSub(slotNum)
            if player.activeWeaponSlot == slotNum then
                return player.autoGun and "Auto+aim" or "Manual"
            end
            return "TAB"
        end

        local slot2Label, slot2Sub, slot2Auto
        if gun2 then
            slot2Label = gun2.name
            slot2Sub   = gunSlotSub(2)
            slot2Auto  = player.activeWeaponSlot == 2 and player.autoGun
        else
            slot2Label = "Melee"
            slot2Sub   = (player.gear.melee and player.gear.melee.name) or "—"
            slot2Auto  = player.autoMelee
        end

        local slots = {

            { id = "gun",    label = gun1 and gun1.name or "Gun",  gun = gun1,
              sub = gunSlotSub(1),
              auto = player.activeWeaponSlot == 1 and player.autoGun,
              isActive = player.activeWeaponSlot == 1 },

            { id = "melee",  label = slot2Label,  gun = gun2,
              sub = slot2Sub,
              auto = slot2Auto,
              isActive = player.activeWeaponSlot == 2 and gun2 ~= nil },

            {

                id = "shield",

                label = "Shield",

                sub = (player.gear.shield and player.gear.shield.name) or "—",

                auto = shieldAutoCapable and player.autoBlock,

                shieldMode = shieldAutoCapable,

            },

        }



        love.graphics.setFont(HUD._fontHudSm)

        shadowPrint("TAB switch · RMB auto · R reload", LOADOUT_BASE_X, baseY - 16, 0.68, 0.66, 0.62, 0.88)



        for i, slot in ipairs(slots) do

            local x = LOADOUT_BASE_X + (i - 1) * (LOADOUT_SLOT_W + LOADOUT_GAP)

            local borderOn = slot.auto



            -- Active weapon slot highlight (bright gold border)
            if slot.isActive then
                love.graphics.setColor(0.92, 0.75, 0.25, 0.75)
                love.graphics.setLineWidth(2)
                love.graphics.rectangle("line", x - 2, baseY - 2, LOADOUT_SLOT_W + 4, LOADOUT_SLOT_H + 4)
                love.graphics.setLineWidth(1)
            end

            if borderOn then

                love.graphics.setColor(0.25, 0.85, 0.48, 0.55)

                love.graphics.setLineWidth(2)

                love.graphics.rectangle("line", x - 1, baseY - 1, LOADOUT_SLOT_W + 2, LOADOUT_SLOT_H + 2)

                love.graphics.setLineWidth(1)

            end



            if slot.id == "melee" and player.meleeHitFlashTimer > 0 then

                local p = player.meleeHitFlashTimer / 0.2

                love.graphics.setColor(1, 0.45, 0.2, 0.35 + 0.45 * p)

                love.graphics.setLineWidth(2)

                love.graphics.rectangle("line", x - 2, baseY - 2, LOADOUT_SLOT_W + 4, LOADOUT_SLOT_H + 4)

                love.graphics.setLineWidth(1)

            end



            -- Draw weapon sprite or text label inside slot
            local sprite = slot.gun and Guns.getSprite(slot.gun)
            if sprite then
                local sw, sh = sprite:getDimensions()
                local maxW = LOADOUT_SLOT_W - 8
                local maxH = LOADOUT_SLOT_H - 22  -- leave room for sub text
                local sc = math.min(maxW / sw, maxH / sh)
                local dx = x + (LOADOUT_SLOT_W - sw * sc) / 2
                local dy = baseY + (maxH - sh * sc) / 2 + 2
                love.graphics.setColor(1, 1, 1, borderOn and 1 or 0.78)
                love.graphics.draw(sprite, dx, dy, 0, sc, sc)
            else
                love.graphics.setFont(HUD._fontLoadout)
                shadowPrintf(slot.label, x + 4, baseY + 4, LOADOUT_SLOT_W - 8, "center", 0.95, 0.9, 0.82, borderOn and 1 or 0.78)
            end



            love.graphics.setFont(HUD._fontLoadoutSm)

            love.graphics.setColor(0.82, 0.8, 0.85, borderOn and 0.92 or 0.58)

            shadowPrintf(slot.sub, x + 4, baseY + 22, LOADOUT_SLOT_W - 8, "center", 0.78, 0.76, 0.8, borderOn and 0.92 or 0.58)



            love.graphics.setFont(HUD._fontLoadoutSm)

            if slot.id == "shield" and not slot.shieldMode then

                love.graphics.setColor(0.55, 0.55, 0.58, 0.85)

                shadowPrintf("CTRL", x + 4, baseY + 36, LOADOUT_SLOT_W - 8, "center", 0.65, 0.64, 0.68, 0.85)

            else

                love.graphics.setColor(0.45, 0.92, 0.58, borderOn and 1 or 0.4)

                shadowPrintf(borderOn and "AUTO" or "off", x + 4, baseY + 36, LOADOUT_SLOT_W - 8, "center", 0.42, 0.88, 0.55, borderOn and 1 or 0.4)

            end

        end

    end



    love.graphics.setFont(prevFont)

    love.graphics.pop()

    love.graphics.setColor(1, 1, 1)

end



function HUD.drawRoomInfo(roomIndex, totalRooms)

    ensureFonts()

    love.graphics.push()

    love.graphics.origin()



    local w = 320

    local x = (GAME_WIDTH - w) / 2

    local y = 16

    love.graphics.setFont(HUD._fontRoom)

    local text = string.format("Room %d / %d", roomIndex, totalRooms)

    shadowPrintf(text, x, y, w, "center", 0.92, 0.86, 0.76, 1)



    love.graphics.pop()

    love.graphics.setColor(1, 1, 1)

end



--- Full-screen tint + title when Dead Eye is active (call after camera detach).

function HUD.drawDeadEye(player)

    if not player or player.deadEyeTimer <= 0 then return end

    ensureFonts()

    love.graphics.push()

    love.graphics.origin()

    love.graphics.setColor(0.35, 0.05, 0.05, 0.28)

    love.graphics.rectangle("fill", 0, 0, GAME_WIDTH, GAME_HEIGHT)

    love.graphics.setFont(HUD._fontDeadEye)

    shadowPrintf("DEAD EYE", 0, GAME_HEIGHT * 0.5 - 100, GAME_WIDTH, "center", 1, 0.45, 0.2, 1)

    love.graphics.pop()

    love.graphics.setColor(1, 1, 1)

end



return HUD


