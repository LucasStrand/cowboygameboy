local Font = require("src.ui.font")
local Guns = require("src.data.guns")
local GearIcons = require("src.ui.gear_icons")
local GoldCoin = require("src.ui.gold_coin")

local HUD = {}

-- ════════════════════════════════════════════════════════
-- SPRITE SHEET
-- ════════════════════════════════════════════════════════

local SPRITE_RECTS = {
    hpBar    = {80, 60, 1024, 64},
    xpBar    = {80, 156, 1024, 64},
    slot     = {80, 260, 256, 208},
    coin     = {80, 508, 64, 64},
    heart    = {280, 508, 64, 64},
    star     = {480, 508, 64, 64},
    banner   = {40, 608, 1280, 140},
    cornerTL = {80, 840, 64, 64},
    cornerTR = {180, 840, 64, 64},
    cornerBL = {280, 840, 64, 64},
    cornerBR = {380, 840, 64, 64},
}

-- Display scales
local BAR_SCALE    = 0.35   -- 1024×0.35 ≈ 358,  64×0.35 ≈ 22
local ICON_SCALE   = 0.25   -- 64×0.25 = 16
local CORNER_SCALE = 0.30   -- 64×0.30 ≈ 19

-- Slot layout: large frames in a triangle, NO overlap
local SLOT_SCALE   = 0.40   -- 256×0.40 = 102,  208×0.40 = 83
local SLOT_W       = math.floor(256 * SLOT_SCALE)  -- 102
local SLOT_H       = math.floor(208 * SLOT_SCALE)  -- 83
local SLOT_BASE_X  = 8
local SLOT_GAP     = 6      -- gap between slots

-- Triangle arrangement: gun top-left, melee top-right, shield bottom-centre
-- No overlap: melee starts after gun + gap, shield centred below
local SLOT_OFFSETS = {
    {dx = 0,                    dy = 0},                    -- gun (top-left)
    {dx = SLOT_W + SLOT_GAP,    dy = 0},                    -- melee (top-right)
    {dx = (SLOT_W + SLOT_GAP) / 2, dy = SLOT_H + SLOT_GAP}, -- shield (bottom-centre)
}

-- Precomputed display sizes
local BAR_W    = math.floor(1024 * BAR_SCALE)
local BAR_H    = math.floor(64 * BAR_SCALE)
local ICON_SZ  = math.floor(64 * ICON_SCALE)
local CORNER_SZ = math.floor(64 * CORNER_SCALE)

-- Inner fill insets at original sprite scale (measured from pixel data)
local HP_INSET  = {l = 24, t = 16, r = 24, b = 16}
local XP_INSET  = {l = 24, t = 20, r = 24, b = 20}

-- Cluster bounding box
local CLUSTER_W = SLOT_OFFSETS[2].dx + SLOT_W             -- rightmost edge
local CLUSTER_H = SLOT_OFFSETS[3].dy + SLOT_H             -- bottommost edge

local function slotBaseY(screenH)
    return screenH - CLUSTER_H - 20
end

-- ── Hit test (matches staggered draw positions) ──
-- Check back-to-front so topmost (last-drawn) slot wins on overlap
function HUD.hitLoadout(mx, my, screenH)
    local baseY = slotBaseY(screenH)
    local order = { "gun", "melee", "shield" }
    for i = #order, 1, -1 do
        local s = SLOT_OFFSETS[i]
        local x = SLOT_BASE_X + s.dx
        local y = baseY + s.dy
        if mx >= x and mx <= x + SLOT_W and my >= y and my <= y + SLOT_H then
            return order[i]
        end
    end
    return nil
end

local function loadSprites()
    if HUD._spriteLoaded then return end
    HUD._spriteLoaded = true

    local ok, sheet = pcall(love.graphics.newImage, "assets/ui/western_cowboy_roguelike_hud_sprite_sheet.png")
    if not ok then
        HUD._sheet = nil
        return
    end
    sheet:setFilter("linear", "linear")
    HUD._sheet = sheet

    local sw, sh = sheet:getDimensions()
    HUD._quads = {}
    for name, r in pairs(SPRITE_RECTS) do
        HUD._quads[name] = love.graphics.newQuad(r[1], r[2], r[3], r[4], sw, sh)
    end
end

--- Spell icon for Dead Man's Hand (assets/ui copy of VerArc lightning_spell; independent of HUD sheet load).
local function ensureUltIcon()
    if HUD._ultIconLoaded then return end
    HUD._ultIconLoaded = true
    local ok, img = pcall(love.graphics.newImage, "assets/ui/ult_dead_mans_hand.png")
    if ok and img then
        img:setFilter("nearest", "nearest")
        HUD._ultIcon = img
    end
end

local function drawSprite(name, x, y, scale, r, g, b, a)
    if not HUD._sheet then return end
    love.graphics.setColor(r or 1, g or 1, b or 1, a or 1)
    love.graphics.draw(HUD._sheet, HUD._quads[name], math.floor(x), math.floor(y), 0, scale, scale)
end

-- ════════════════════════════════════════════════════════
-- FONTS
-- ════════════════════════════════════════════════════════

local function ensureFonts()
    if HUD._fontHud then return end
    HUD._fontHud = Font.hudPrimary()
    HUD._fontHudSm = Font.hudSecondary()
    HUD._lineH = HUD._fontHud:getHeight()
    HUD._lineHSm = HUD._fontHudSm:getHeight()
    HUD._fontLoadout = Font.new(11)
    HUD._fontRoom = Font.new(16)
    HUD._fontDeadEye = Font.new(36)
    HUD._fontGold = Font.new(24)
end

-- ════════════════════════════════════════════════════════
-- TEXT HELPERS
-- ════════════════════════════════════════════════════════

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

-- ════════════════════════════════════════════════════════
-- AMMO DISPLAYS
-- ════════════════════════════════════════════════════════

local function drumOuterRadius(n)
    n = math.max(1, math.floor(n))
    return math.max(36, math.min(54, 30 + n * 0.75))
end

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

local function drawDoubleBarrel(cx, cy, capacity, loadedCount, reloading)
    capacity = math.max(1, math.floor(capacity))
    loadedCount = math.max(0, math.min(capacity, math.floor(loadedCount)))

    local barrelR = 14
    local bGap = 6
    local totalH = capacity * (barrelR * 2 + bGap) - bGap
    local startY = cy - totalH / 2 + barrelR

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
        local by = startY + (i - 1) * (barrelR * 2 + bGap)
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

local function drawMagazineCounter(cx, cy, capacity, loadedCount, reloading)
    capacity = math.max(1, math.floor(capacity))
    loadedCount = math.max(0, math.min(capacity, math.floor(loadedCount)))

    local magW, magH = 28, 56
    local mx = cx - magW / 2
    local my = cy - magH / 2

    love.graphics.setColor(0.11, 0.1, 0.09)
    love.graphics.rectangle("fill", mx - 1, my - 1, magW + 2, magH + 2, 3, 3)
    love.graphics.setColor(0.28, 0.32, 0.22)
    love.graphics.rectangle("fill", mx, my, magW, magH, 2, 2)

    local fillRatio = loadedCount / capacity
    local fillH = math.floor((magH - 4) * fillRatio)
    if fillH > 0 then
        love.graphics.setColor(0.45, 0.52, 0.3)
        love.graphics.rectangle("fill", mx + 2, my + magH - 2 - fillH, magW - 4, fillH)
        love.graphics.setColor(0.58, 0.65, 0.4, 0.5)
        love.graphics.rectangle("fill", mx + 2, my + magH - 2 - fillH, magW - 4, math.min(2, fillH))
    end

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

    if not HUD._fontMag then
        HUD._fontMag = Font.new(18)
    end
    local prev = love.graphics.getFont()
    love.graphics.setFont(HUD._fontMag)
    local numStr = tostring(loadedCount)
    local tw = HUD._fontMag:getWidth(numStr)
    local th = HUD._fontMag:getHeight()
    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.print(numStr, cx - tw / 2 + 1, cy - th / 2 + 1)
    if loadedCount <= math.ceil(capacity * 0.2) then
        love.graphics.setColor(1, 0.3, 0.2)
    else
        love.graphics.setColor(1, 0.95, 0.85)
    end
    love.graphics.print(numStr, cx - tw / 2, cy - th / 2)
    love.graphics.setFont(prev)
end

local BASE_CYLINDER_SIZE = 6
local function gunCapacity(gun, player, slotIndex)
    if slotIndex and player.getResolvedWeaponStats then
        local stats = player:getResolvedWeaponStats(slotIndex)
        if stats and stats.cylinderSize then
            return stats.cylinderSize
        end
    end
    local perkDelta = player.stats.cylinderSize - BASE_CYLINDER_SIZE
    return gun.baseStats.cylinderSize + perkDelta
end

local function drawAmmoDisplay(cx, cy, player, effectiveStats)
    local gun = player:getActiveGun()
    if not gun then return 0 end

    local cap = gunCapacity(gun, player, player.activeWeaponSlot)
    local ammoType = gun.ammoType
    if ammoType == "cylinder" then
        drawRevolverCylinder(cx, cy, cap, player.ammo, player.reloading)
        return drumOuterRadius(cap)
    elseif ammoType == "double_barrel" then
        drawDoubleBarrel(cx, cy, cap, player.ammo, player.reloading)
        return 24
    elseif ammoType == "magazine" then
        drawMagazineCounter(cx, cy, cap, player.ammo, player.reloading)
        return 30
    end
    return 0
end

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

-- ════════════════════════════════════════════════════════
-- DRAW HELPERS: sprite-backed bar
-- ════════════════════════════════════════════════════════

local function drawSpriteBar(spriteName, inset, bx, by, ratio, fr, fg, fb, hr, hg, hb, ha)
    -- 1) Draw the frame sprite first (its dark interior = empty bar background)
    drawSprite(spriteName, bx, by, BAR_SCALE)

    -- 2) Draw coloured fill ON TOP, inside the border area
    local fillX = bx + inset.l * BAR_SCALE
    local fillY = by + inset.t * BAR_SCALE
    local fillW = (1024 - inset.l - inset.r) * BAR_SCALE
    local fillH = (64 - inset.t - inset.b) * BAR_SCALE

    if ratio > 0 then
        love.graphics.setColor(fr, fg, fb)
        love.graphics.rectangle("fill", fillX, fillY, fillW * ratio, fillH)
        love.graphics.setColor(hr, hg, hb, ha)
        love.graphics.rectangle("fill", fillX, fillY, fillW * ratio, math.min(2, fillH))
    end
end

-- ════════════════════════════════════════════════════════
-- MAIN DRAW
-- ════════════════════════════════════════════════════════

function HUD.draw(player)
    ensureFonts()
    loadSprites()
    ensureUltIcon()

    love.graphics.push()
    love.graphics.origin()

    local screenW = GAME_WIDTH
    local screenH = GAME_HEIGHT
    local effectiveStats = player:getEffectiveStats()
    local prevFont = love.graphics.getFont()

    -- ── Corner decorations (all four corners) ──
    if HUD._sheet then
        local pad = 4
        drawSprite("cornerTL", pad, pad, CORNER_SCALE)
        drawSprite("cornerTR", screenW - CORNER_SZ - pad, pad, CORNER_SCALE)
        drawSprite("cornerBL", pad, screenH - CORNER_SZ - pad, CORNER_SCALE)
        drawSprite("cornerBR", screenW - CORNER_SZ - pad, screenH - CORNER_SZ - pad, CORNER_SCALE)
    end

    -- ── HP + XP bars (bottom centre) ──
    do
        local hpRatio = math.max(0, math.min(1, player.hp / math.max(1, effectiveStats.maxHP)))
        local xpRatio = math.max(0, math.min(1, player.xp / player.xpToNext))

        local lineH = HUD._lineH
        local rowGap = 4

        local iconGap = 6
        local totalW = ICON_SZ + iconGap + BAR_W
        local barX = math.floor((screenW - totalW) / 2) + ICON_SZ + iconGap
        local iconX = barX - iconGap - ICON_SZ

        local bottomPad = 24
        local xpBarY  = screenH - bottomPad - BAR_H
        local xpTextY = xpBarY - lineH + 2
        local hpBarY  = xpTextY - rowGap - BAR_H
        local hpTextY = hpBarY - lineH + 2

        -- HP
        love.graphics.setFont(HUD._fontHud)
        shadowPrintf(
            string.format("HP: %d / %d", player.hp, effectiveStats.maxHP),
            barX, hpTextY, BAR_W, "center",
            0.95, 0.85, 0.75, 1
        )
        drawSpriteBar("hpBar", HP_INSET, barX, hpBarY, hpRatio,
            0.9, 0.26, 0.2,
            1, 0.55, 0.45, 0.4)
        drawSprite("heart", iconX, hpBarY + (BAR_H - ICON_SZ) / 2, ICON_SCALE)

        -- XP
        love.graphics.setFont(HUD._fontHud)
        shadowPrintf(
            string.format("LV %d  ·  XP %d / %d", player.level, player.xp, player.xpToNext),
            barX, xpTextY, BAR_W, "center",
            0.78, 0.88, 0.98, 0.95
        )
        drawSpriteBar("xpBar", XP_INSET, barX, xpBarY, xpRatio,
            0.25, 0.48, 0.9,
            0.65, 0.88, 1, 0.35)
        drawSprite("star", iconX, xpBarY + (BAR_H - ICON_SZ) / 2, ICON_SCALE)
    end

    -- ── Gold (top right, coin icon + text, clear of corner decoration) ──
    do
        local coinScale = 0.58  -- 64×0.58 ≈ 37px; matches larger gold digits
        local coinSz = math.floor(64 * coinScale)
        local goldText = string.format("$%d", player.gold)
        love.graphics.setFont(HUD._fontGold)
        local goldLineH = HUD._fontGold:getHeight()
        local textW = HUD._fontGold:getWidth(goldText)
        local totalW = coinSz + 8 + textW
        local gx = screenW - totalW - CORNER_SZ - 18  -- clear of corner ornament
        local gy = 10

        local coinY = gy + (goldLineH - coinSz) / 2
        if not GoldCoin.drawHeadsTopLeft(gx, coinY, coinSz) then
            drawSprite("coin", gx, coinY, coinScale)
        end
        shadowPrint(goldText, gx + coinSz + 8, gy, 1, 0.92, 0.6, 1)
    end

    -- ── Ammo display (above weapon cluster) ──
    do
        local baseY = slotBaseY(screenH)
        local ammoColX = SLOT_BASE_X
        local yCursor = baseY - 8

        if player.blocking then
            love.graphics.setFont(HUD._fontHud)
            local bh = HUD._fontHud:getHeight()
            local by = yCursor - bh
            shadowPrint("BLOCKING", ammoColX + 4, by, 0.55, 0.78, 1, 1)
            yCursor = by - 6
        end

        local isAkimbo = player.isAkimbo and player:isAkimbo()

        if isAkimbo then
            local slot1 = player.weapons[1]
            local slot2 = player.weapons[2]
            local gun1 = slot1 and slot1.gun
            local gun2 = slot2 and slot2.gun

            local function ammoR(gun)
                if not gun then return 20 end
                if gun.ammoType == "cylinder" then
                    return drumOuterRadius(gunCapacity(gun, player, gun == gun1 and 1 or 2))
                elseif gun.ammoType == "double_barrel" then return 24
                elseif gun.ammoType == "magazine" then return 30
                end
                return 20
            end

            local r1 = ammoR(gun1)
            local r2 = ammoR(gun2)
            local agap = 8

            local cx1 = ammoColX + r1
            local cy1 = yCursor - math.max(r1, r2)
            if gun1 then
                local ammo1 = player.activeWeaponSlot == 1 and player.ammo or slot1.ammo
                local reloading1 = player.activeWeaponSlot == 1 and player.reloading or slot1.reloading
                drawAmmoForGun(cx1, cy1, gun1, gunCapacity(gun1, player, 1), ammo1, reloading1)
            end

            local cx2 = cx1 + r1 + agap + r2
            if gun2 then
                local ammo2 = player.activeWeaponSlot == 2 and player.ammo or slot2.ammo
                local reloading2 = player.activeWeaponSlot == 2 and player.reloading or slot2.reloading
                drawAmmoForGun(cx2, cy1, gun2, gunCapacity(gun2, player, 2), ammo2, reloading2)
            end
        else
            local displayR = 36
            local gun = player:getActiveGun()
            if gun and gun.ammoType == "cylinder" then
                displayR = drumOuterRadius(gunCapacity(gun, player, player.activeWeaponSlot))
            elseif gun and gun.ammoType == "double_barrel" then
                displayR = 24
            elseif gun and gun.ammoType == "magazine" then
                displayR = 30
            end

            local displayCx = ammoColX + CLUSTER_W / 2
            local displayCy = yCursor - displayR
            drawAmmoDisplay(displayCx, displayCy, player, effectiveStats)
        end
    end

    -- ── Weapon slots (bottom-left, staggered triangle cluster) ──
    do
        local baseY = slotBaseY(screenH)
        local shieldAutoCapable = player:shieldAllowsAutoBlock()

        local gun1 = player.weapons[1] and player.weapons[1].gun
        local gun2 = player.weapons[2] and player.weapons[2].gun

        local slot2Auto
        if gun2 then
            slot2Auto = player.autoGun and player:getWeaponSlotForAutoFire() == 2
        else
            slot2Auto = player.autoMelee
        end

        local meleeLabel = gun2 and gun2.name
            or (player.gear.melee and player.gear.melee.name) or "Melee"
        local shieldLabel = (player.gear.shield and player.gear.shield.name) or "Shield"

        local slots = {
            { id = "gun",   label = gun1 and gun1.name or "Gun",  gun = gun1,
              auto = player.autoGun and player:getWeaponSlotForAutoFire() == 1,
              isActive = player.activeWeaponSlot == 1 },

            { id = "melee", label = meleeLabel, gun = gun2,
              gearIcon = (not gun2) and player.gear.melee or nil,
              auto = slot2Auto,
              isActive = player.activeWeaponSlot == 2 },

            { id = "shield", label = shieldLabel,
              gearIcon = player.gear.shield,
              auto = shieldAutoCapable and player.autoBlock,
              shieldMode = shieldAutoCapable },
        }

        -- Draw slots in order (1→3), so last-drawn is visually on top
        for i, slot in ipairs(slots) do
            local off = SLOT_OFFSETS[i]
            local x = SLOT_BASE_X + off.dx
            local y = baseY + off.dy
            local borderOn = slot.auto

            -- Ornate frame sprite
            if HUD._sheet then
                drawSprite("slot", x, y, SLOT_SCALE)
            else
                love.graphics.setColor(0.1, 0.08, 0.07, 0.85)
                love.graphics.rectangle("fill", x, y, SLOT_W, SLOT_H, 3, 3)
            end

            -- Active weapon highlight (gold)
            if slot.isActive then
                love.graphics.setColor(0.92, 0.75, 0.25, 0.75)
                love.graphics.setLineWidth(2)
                love.graphics.rectangle("line", x - 2, y - 2, SLOT_W + 4, SLOT_H + 4)
                love.graphics.setLineWidth(1)
            end

            -- Auto border (green)
            if borderOn then
                love.graphics.setColor(0.25, 0.85, 0.48, 0.55)
                love.graphics.setLineWidth(2)
                love.graphics.rectangle("line", x - 1, y - 1, SLOT_W + 2, SLOT_H + 2)
                love.graphics.setLineWidth(1)
            end

            -- Melee hit flash
            if slot.id == "melee" and player.meleeHitFlashTimer > 0 then
                local p = player.meleeHitFlashTimer / 0.2
                love.graphics.setColor(1, 0.45, 0.2, 0.35 + 0.45 * p)
                love.graphics.setLineWidth(2)
                love.graphics.rectangle("line", x - 2, y - 2, SLOT_W + 4, SLOT_H + 4)
                love.graphics.setLineWidth(1)
            end

            -- Weapon sprite (fills as much of the frame as possible)
            local sprite = slot.gun and Guns.getSprite(slot.gun)
            local pad = 4  -- tight fit, frame border provides visual padding
            local drawn = false
            if sprite then
                local sw, sh = sprite:getDimensions()
                local maxW = SLOT_W - pad * 2
                local maxH = SLOT_H - pad * 2
                local sc = math.min(maxW / sw, maxH / sh)
                local dx = x + (SLOT_W - sw * sc) / 2
                local dy = y + (SLOT_H - sh * sc) / 2
                love.graphics.setColor(1, 1, 1, borderOn and 1 or 0.85)
                love.graphics.draw(sprite, dx, dy, 0, sc, sc)
                drawn = true
            elseif slot.gearIcon and slot.gearIcon.icon then
                drawn = GearIcons.draw(slot.gearIcon.icon, x, y, SLOT_W, SLOT_H, pad,
                    borderOn and 1 or 0.88)
            end
            if not drawn then
                -- Fallback: short label centred in frame
                love.graphics.setFont(HUD._fontLoadout)
                shadowPrintf(slot.label, x, y + (SLOT_H - HUD._fontLoadout:getHeight()) / 2,
                    SLOT_W, "center", 0.9, 0.85, 0.78, borderOn and 1 or 0.65)
            end
        end

        -- ── Q Ultimate slot (right of cluster, vertically centred) ──
        do
            local ultX = SLOT_BASE_X + CLUSTER_W + SLOT_GAP + 4
            local ultY = baseY + (CLUSTER_H - SLOT_H) / 2
            local charge = player.ultCharge or 0
            local isReady = charge >= 1
            local isActive = player.ultActive

            -- Frame
            if HUD._sheet then
                drawSprite("slot", ultX, ultY, SLOT_SCALE)
            else
                love.graphics.setColor(0.1, 0.08, 0.07, 0.85)
                love.graphics.rectangle("fill", ultX, ultY, SLOT_W, SLOT_H, 3, 3)
            end

            -- Charge fill (bottom-up inside the frame)
            if charge > 0 and not isActive then
                local fillPad = 10
                local fillW = SLOT_W - fillPad * 2
                local fillH = (SLOT_H - fillPad * 2) * charge
                local fillX = ultX + fillPad
                local fillY = ultY + SLOT_H - fillPad - fillH
                if isReady then
                    -- Pulsing gold glow when ready
                    local pulse = 0.6 + 0.4 * math.sin(love.timer.getTime() * 4)
                    love.graphics.setColor(0.95, 0.75, 0.2, 0.5 * pulse)
                else
                    love.graphics.setColor(0.85, 0.55, 0.15, 0.35)
                end
                love.graphics.rectangle("fill", fillX, fillY, fillW, fillH)
            end

            -- Spell icon (Dead Man's Hand) — above Q label; charge fill behind
            if HUD._ultIcon then
                local labelH = HUD._fontLoadout:getHeight()
                local iconPad = 10
                local labelGap = 5
                local iw, ih = HUD._ultIcon:getDimensions()
                local maxW = SLOT_W - iconPad * 2
                local maxH = SLOT_H - iconPad * 2 - labelH - labelGap
                local sc = math.min(maxW / iw, maxH / ih)
                local dw, dh = iw * sc, ih * sc
                local dx = ultX + (SLOT_W - dw) / 2
                local dy = ultY + iconPad
                local ia = 0.7
                if isReady then ia = 1
                elseif isActive then
                    ia = 0.88 + 0.12 * math.sin(love.timer.getTime() * 14)
                end
                love.graphics.setColor(1, 1, 1, ia)
                love.graphics.draw(HUD._ultIcon, math.floor(dx), math.floor(dy), 0, sc, sc)
            end

            -- Ready border (pulsing gold)
            if isReady and not isActive then
                local pulse = 0.5 + 0.5 * math.sin(love.timer.getTime() * 5)
                love.graphics.setColor(0.95, 0.78, 0.2, 0.6 + 0.4 * pulse)
                love.graphics.setLineWidth(2)
                love.graphics.rectangle("line", ultX - 2, ultY - 2, SLOT_W + 4, SLOT_H + 4)
                love.graphics.setLineWidth(1)
            end

            -- Active border (bright white)
            if isActive then
                love.graphics.setColor(1, 0.9, 0.5, 0.9)
                love.graphics.setLineWidth(3)
                love.graphics.rectangle("line", ultX - 3, ultY - 3, SLOT_W + 6, SLOT_H + 6)
                love.graphics.setLineWidth(1)
            end

            -- "Q" label + charge percentage (bottom strip)
            love.graphics.setFont(HUD._fontLoadout)
            local qLabel = isReady and "Q READY" or string.format("Q %d%%", math.floor(charge * 100))
            local qAlpha = isReady and 1 or 0.6
            local qR, qG, qB = 0.9, 0.85, 0.78
            if isReady then qR, qG, qB = 0.95, 0.82, 0.3 end
            local labelH2 = HUD._fontLoadout:getHeight()
            shadowPrintf(qLabel, ultX, ultY + SLOT_H - labelH2 - 4,
                SLOT_W, "center", qR, qG, qB, qAlpha)
        end
    end

    -- ── Active buff/debuff icons (just above HP label, aligned with bar column) ──
    if player.buffs then
        local Buffs = require("src.systems.buffs")
        local lineH = HUD._lineH
        local rowGap = 4
        local bottomPad = 24
        local iconGap = 6
        local totalW = ICON_SZ + iconGap + BAR_W
        local barX = math.floor((screenW - totalW) / 2) + ICON_SZ + iconGap
        local iconX = barX - iconGap - ICON_SZ
        local xpBarY = screenH - bottomPad - BAR_H
        local xpTextY = xpBarY - lineH + 2
        local hpBarY = xpTextY - rowGap - BAR_H
        local hpTextY = hpBarY - lineH + 2
        local buffScale = 2
        local buffRowH = 16 * buffScale + 3
        local buffY = hpTextY - 8 - buffRowH
        local buffX = math.max(6, iconX - 2)
        Buffs.drawIcons(player.buffs, buffX, buffY, buffScale)
    end

    love.graphics.setFont(prevFont)
    love.graphics.pop()
    love.graphics.setColor(1, 1, 1)
end

-- ════════════════════════════════════════════════════════
-- ROOM INFO (procedural dark panel with western trim)
-- ════════════════════════════════════════════════════════

function HUD.drawRoomInfo(roomIndex, totalRooms)
    ensureFonts()

    love.graphics.push()
    love.graphics.origin()

    local screenW = GAME_WIDTH
    local text = string.format("Room %d / %d", roomIndex, totalRooms)

    love.graphics.setFont(HUD._fontRoom)
    local textW = HUD._fontRoom:getWidth(text)
    local textH = HUD._fontRoom:getHeight()

    local padX, padY = 28, 8
    local panelW = textW + padX * 2
    local panelH = textH + padY * 2
    local px = math.floor((screenW - panelW) / 2)
    local py = 8

    -- Dark panel
    love.graphics.setColor(0.06, 0.05, 0.04, 0.88)
    love.graphics.rectangle("fill", px, py, panelW, panelH, 4, 4)

    -- Warm wood-tone border
    love.graphics.setColor(0.55, 0.38, 0.22, 0.85)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", px, py, panelW, panelH, 4, 4)
    love.graphics.setLineWidth(1)

    -- Inner highlight
    love.graphics.setColor(0.65, 0.5, 0.3, 0.25)
    love.graphics.rectangle("line", px + 3, py + 3, panelW - 6, panelH - 6, 2, 2)

    -- Side dashes (decorative)
    love.graphics.setColor(0.5, 0.38, 0.25, 0.5)
    local dashY = py + panelH / 2
    love.graphics.setLineWidth(1)
    love.graphics.line(px - 18, dashY, px - 3, dashY)
    love.graphics.line(px + panelW + 3, dashY, px + panelW + 18, dashY)

    -- Text
    shadowPrintf(text, px, py + padY, panelW, "center", 0.95, 0.88, 0.75, 1)

    love.graphics.pop()
    love.graphics.setColor(1, 1, 1)
end

-- ════════════════════════════════════════════════════════
-- DEAD EYE overlay
-- ════════════════════════════════════════════════════════

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
