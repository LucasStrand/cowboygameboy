local Font = require("src.ui.font")

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
    if HUD._fontLabel then return end
    HUD._fontLabel = Font.new(12)
    HUD._fontBody = Font.new(16)
    HUD._fontSmall = Font.new(11)
    HUD._fontLoadout = Font.new(11)
    HUD._fontLoadoutSm = Font.new(10)
    HUD._fontRoom = Font.new(14)
    HUD._fontHint = Font.new(10)
    HUD._fontDeadEye = Font.new(22)
end

-- Dark outline for readability on busy backgrounds
local function shadowPrint(text, x, y, r, g, b, a)
    a = a or 1
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

local function westernFrame(x, y, w, h)
    love.graphics.setColor(0, 0, 0, 0.35)
    love.graphics.rectangle("fill", x + 4, y + 4, w, h)
    love.graphics.setColor(0.09, 0.07, 0.06, 0.94)
    love.graphics.rectangle("fill", x, y, w, h)
    love.graphics.setColor(0.42, 0.32, 0.22, 0.55)
    love.graphics.rectangle("fill", x + 2, y + 2, w - 4, 3)
    love.graphics.setColor(0.28, 0.22, 0.16, 0.95)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x, y, w, h)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(0.12, 0.1, 0.08, 0.9)
    love.graphics.rectangle("line", x + 1, y + 1, w - 2, h - 2)
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

function HUD.draw(player)
    ensureFonts()
    love.graphics.push()
    love.graphics.origin()

    local screenW = GAME_WIDTH
    local screenH = GAME_HEIGHT
    local effectiveStats = player:getEffectiveStats()

    local prevFont = love.graphics.getFont()

    -- —— XP bar (bottom) ——
    local xpBarW = 340
    local xpBarH = 14
    local xpBarX = (screenW - xpBarW) / 2
    local xpBarY = screenH - 36
    local xpRatio = math.max(0, math.min(1, player.xp / player.xpToNext))

    westernFrame(xpBarX - 8, xpBarY - 26, xpBarW + 16, xpBarH + 32)

    love.graphics.setColor(0.12, 0.14, 0.22)
    love.graphics.rectangle("fill", xpBarX, xpBarY, xpBarW, xpBarH)
    love.graphics.setColor(0.15, 0.28, 0.55)
    love.graphics.rectangle("fill", xpBarX, xpBarY, xpBarW * xpRatio, xpBarH)
    love.graphics.setColor(0.35, 0.65, 1)
    love.graphics.rectangle("fill", xpBarX, xpBarY, xpBarW * xpRatio, xpBarH)
    love.graphics.setColor(0.55, 0.82, 1, 0.4)
    love.graphics.rectangle("fill", xpBarX, xpBarY, xpBarW * xpRatio, 4)

    love.graphics.setFont(HUD._fontLabel)
    shadowPrintf("LV " .. player.level, xpBarX, xpBarY - 22, xpBarW, "center", 0.9, 0.85, 0.75, 1)

    love.graphics.setFont(HUD._fontSmall)
    local xpStr = string.format("%d  /  %d  XP", player.xp, player.xpToNext)
    shadowPrintf(xpStr, xpBarX, xpBarY + xpBarH + 4, xpBarW, "center", 0.75, 0.8, 0.88, 0.95)

    -- —— Gold (top right) ——
    local goldW = 168
    local goldX = screenW - goldW - 12
    local goldY = 12
    westernFrame(goldX, goldY, goldW, 44)
    love.graphics.setFont(HUD._fontSmall)
    love.graphics.setColor(0.75, 0.65, 0.55, 1)
    shadowPrint("Gold", goldX + 12, goldY + 8, 0.85, 0.78, 0.68, 1)
    love.graphics.setFont(HUD._fontBody)
    local gStr = "$ " .. player.gold
    shadowPrintf(gStr, goldX, goldY + 20, goldW - 16, "right", 1, 0.88, 0.38, 1)

    -- —— Loadout row + revolver drum (bottom-left) ——
    do
        local baseY = loadoutBaseY(screenH)
        local cyl = effectiveStats.cylinderSize
        local drumR = drumOuterRadius(cyl)
        local ammoColX = LOADOUT_BASE_X
        local bannerW = math.max(148, math.floor(drumR * 2.35))

        -- Stack upward from just above the RMB hint (reload bar is drawn above the player in world space)
        local hintY = baseY - 16
        local yCursor = hintY - 8

        if player.blocking then
            love.graphics.setFont(HUD._fontLabel)
            local bh = 26
            local by = yCursor - bh
            love.graphics.setColor(0.12, 0.2, 0.45, 0.92)
            love.graphics.rectangle("fill", ammoColX - 4, by - 4, bannerW + 8, bh)
            love.graphics.setColor(0.45, 0.65, 1, 0.95)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", ammoColX - 4, by - 4, bannerW + 8, bh)
            love.graphics.setLineWidth(1)
            shadowPrint("[  BLOCKING  ]", ammoColX + 4, by, 0.75, 0.88, 1, 1)
            yCursor = by - 4
        end

        local drumCy = yCursor - drumR
        local drumCx = ammoColX + drumR
        drawRevolverCylinder(drumCx, drumCy, cyl, player.ammo, player.reloading)
    end

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

        love.graphics.setFont(HUD._fontHint)
        love.graphics.setColor(0.62, 0.58, 0.52, 0.85)
        shadowPrint("Right-click slot: toggle auto", LOADOUT_BASE_X, baseY - 16, 0.72, 0.68, 0.62, 0.9)

        love.graphics.setFont(HUD._fontLoadout)
        for i, slot in ipairs(slots) do
            local x = LOADOUT_BASE_X + (i - 1) * (LOADOUT_SLOT_W + LOADOUT_GAP)
            love.graphics.setColor(0.06, 0.05, 0.05, 0.96)
            love.graphics.rectangle("fill", x, baseY, LOADOUT_SLOT_W, LOADOUT_SLOT_H)

            local borderOn = slot.auto
            if borderOn then
                love.graphics.setColor(0.2, 0.75, 0.42, 0.98)
            else
                love.graphics.setColor(0.4, 0.36, 0.32, 0.88)
            end
            love.graphics.setLineWidth(borderOn and 3 or 2)
            love.graphics.rectangle("line", x, baseY, LOADOUT_SLOT_W, LOADOUT_SLOT_H)
            love.graphics.setLineWidth(1)

            if slot.id == "melee" and player.meleeHitFlashTimer > 0 then
                local p = player.meleeHitFlashTimer / 0.2
                love.graphics.setColor(1, 0.42, 0.15, 0.5 + 0.5 * p)
                love.graphics.setLineWidth(4)
                love.graphics.rectangle("line", x - 2, baseY - 2, LOADOUT_SLOT_W + 4, LOADOUT_SLOT_H + 4)
                love.graphics.setLineWidth(1)
            end

            love.graphics.setFont(HUD._fontLoadout)
            love.graphics.setColor(1, 1, 1, borderOn and 1 or 0.72)
            shadowPrintf(slot.label, x + 4, baseY + 5, LOADOUT_SLOT_W - 8, "center", 0.95, 0.92, 0.88, borderOn and 1 or 0.72)

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

    local w = 200
    local x = (GAME_WIDTH - w) / 2
    local y = 14
    westernFrame(x, y, w, 36)
    love.graphics.setFont(HUD._fontRoom)
    local text = string.format("Room  %d  /  %d", roomIndex, totalRooms)
    shadowPrintf(text, x, y + 10, w, "center", 0.92, 0.86, 0.76, 1)

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
